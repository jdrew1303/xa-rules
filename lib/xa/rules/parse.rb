require 'parslet'

module XA
  module Rules
    module Parse
      class ActionParser < Parslet::Parser
        rule(:comma)        { str(',') }
        rule(:colon)        { str(':') }
        rule(:lblock)       { str('[') }
        rule(:rblock)       { str(']') }
        rule(:lparen)       { str('(') }
        rule(:rparen)       { str(')') }
        
        rule(:space)        { match('\s').repeat(1) }
        rule(:ass)          { str('AS') }
        rule(:usings)       { str('USING') }
        rule(:includes)     { str('INCLUDE') }
        rule(:pushs)        { str('PUSH') }
        rule(:pops)         { str('POP') }
        rule(:duplicates)   { str('DUPLICATE') }
        rule(:pulls)        { str('PULL') }
        rule(:attachs)      { str('ATTACH') }
        rule(:invokes)      { str('INVOKE') }

        rule(:names)        { name >> (comma >> space.maybe >> name).repeat }
        rule(:name)         { match('\w+').repeat(1) }
        rule(:names_as)     { name_as >> (comma >> space.maybe >> name_as).repeat }
        rule(:name_as)      { name.as(:original) >> (space >> ass >> space >> name.as(:new)).maybe }
        rule(:anything)     { match('[^\s]').repeat(1) }
        
        rule(:table_ref)      { name.as(:table_name) >> lblock >> names.as(:columns) >> rblock }
        rule(:table_ref_opt)  { name.as(:table_name) >> (lblock >> names.as(:columns) >> rblock).maybe }
        rule(:rule_ref)       { name.as(:ns) >> colon >> name.as(:rule) >> colon >> name.as(:version) }
        rule(:join_spec)      { lblock >> lblock >> names.as(:lefts) >> rblock >> comma >> space.maybe >> lblock >> names.as(:rights) >> rblock >> rblock }
        rule(:includes_spec)  { lblock >> names_as >> rblock }
        rule(:joinish)        { usings >> space >> join_spec.as(:joins) >> space >> includes >> space >> includes_spec.as(:includes) }

        rule(:expects)        { name.as(:action) >> space >> table_ref }
        rule(:commit)         { name.as(:action) >> space >> table_ref_opt }
        rule(:push)           { pushs.as(:action) >> space >> name.as(:table_name) }
        rule(:pop)            { pops.as(:action) }
        rule(:duplicate)      { duplicates.as(:action) }
        rule(:pull)           { pulls.as(:action) >> space >> rule_ref.as(:rule_ref) >> space >> ass >> space >> name.as(:table_name) }
        rule(:attach)         { attachs.as(:action) >> space >> anything.as(:url) >> space >> ass >> space >> name.as(:name) }
        rule(:invoke)         { invokes.as(:action) >> space >> rule_ref.as(:rule_ref) }
        rule(:func)           { name.as(:name) >> lparen >> names.as(:args) >> rparen }
        
        rule(:table_action)   { expects | commit }
        rule(:joinish_action) { name.as(:action) >> space >> joinish }
        rule(:reduce_action)  { name.as(:action) >> space >> name.as(:column) >> space >> usings >> space >> func.as(:function) >> (space >> ass >> space >> name.as(:result)).maybe }
        rule(:stack_action)   { push | pop | duplicate }
        rule(:repo_action)    { attach | pull }
        rule(:rule_action)    { invoke }
        rule(:action)         { table_action | joinish_action | reduce_action | stack_action | repo_action | rule_action }

        root(:action)
      end

      def parse_buffer(b, logger=nil)
        parse(b.split(/\r?\n/).inject([]) do |a, ln|
                ln.strip!
                (ln.empty? || ln.start_with?('#')) ? a : a + [ln]
              end, logger)
      end
      
      def parse(actions, logger=nil)
        rv = {}
        actions.each do |act|
          logger.debug("try to parse: #{act}") if logger
          res = parser.parse(act)
          rv = rv.merge(interpret(rv, res))
        end
        rv
      end

      def unparse(actions, logger=nil)
        actions.map do |act|
          send("unparse_#{act['name']}", act)
        end
      end

      private

      def unparse_pull(act)
        rv = "PULL #{act['namespace']}:#{act['table']}:#{act['version']}"
        rv = "#{rv} AS #{act['as']}" if act.key?('as')
        rv
      end

      def unparse_commit(act)
        rv = "COMMIT #{act['table']}"
        rv = "#{rv}[#{act['columns'].join(', ')}]" if act.key?('columns')
        rv
      end

      def unparse_push(act)
        "PUSH #{act['table']}"
      end

      def unparse_pop(act)
        "POP"
      end

      def unparse_duplicate(act)
        "DUPLICATE"
      end

      def unparse_invoke(act)
        "INVOKE #{act['namespace']}:#{act['rule']}:#{act['version']}"
      end

      def unparse_join(act)
        incs = act.fetch('include', {}).map do |k, v|
          k == v ? k : "#{k} AS #{v}"
        end

        rv = "JOIN USING [[#{act['using']['left'].join(', ')}], [#{act['using']['right'].join(', ')}]]"
        rv = "#{rv} INCLUDE [#{incs.join(', ')}]" if !incs.empty?
        rv
      end

      def unparse_inclusion(act)
        incs = act.fetch('include', {}).map do |k, v|
          k == v ? k : "#{k} AS #{v}"
        end

        rv = "INCLUSION USING [[#{act['using']['left'].join(', ')}], [#{act['using']['right'].join(', ')}]]"
        rv = "#{rv} INCLUDE [#{incs.join(', ')}]" if !incs.empty?
      end
      
      def unparse_accumulate(act)
        rv = "ACCUMULATE #{act['column']} USING #{act['function']['name']}(#{act['function']['args'].join(', ')})"
        rv = "#{rv} AS #{act['result']}" if act.key?('result')
        rv
      end

      def split_names(names)
        names.str.split(/\,\s+/)
      end
      
      def interpret(o, res)
        send("interpret_#{res.fetch(:action, 'nothing').str.downcase}", o, res)
      end

      def interpret_expects(o, res)
        add_meta(o, 'expects', res[:table_name].str => split_names(res[:columns]))
      end

      def interpret_pull(o, res)
        act = {
          'name'      => 'pull',
          'namespace' => res[:rule_ref][:ns].str,
          'table'     => res[:rule_ref][:rule].str,
          'version'   => res[:rule_ref][:version].str,
          'as'        => res[:table_name].str,
        }
        add_action(o, act)
      end

      def interpret_attach(o, res)
        add_meta(o, 'repositories', res[:name].str => res[:url].str)
      end

      def interpret_push(o, res)
        add_action(o, 'name'  => 'push', 'table' => res[:table_name].str)
      end

      def interpret_pop(o, res)
        add_action(o, 'name'  => 'pop')
      end

      def interpret_duplicate(o, res)
        add_action(o, 'name'  => 'duplicate')
      end
      
      def interpret_invoke(o, res)
        act = {
          'name'      => 'invoke',
          'namespace' => res[:rule_ref][:ns].str,
          'rule'      => res[:rule_ref][:rule].str,
          'version'   => res[:rule_ref][:version].str,
        }
        add_action(o, act)
      end
      
      def interpret_commit(o, res)
        add_action(o, {
          'name'  => 'commit',
          'table' => res[:table_name].str,
        }.tap do |a|
          a['columns'] = split_names(res[:columns]) if res.key?(:columns)
        end)
      end

      def interpret_join(o, res)
        interpret_joinish(o, res)
      end

      def interpret_inclusion(o, res)
        interpret_joinish(o, res)
      end
      
      def interpret_joinish(o, res)
        includes = res[:includes].class == Array ? res[:includes] : [res[:includes]]
        add_action(o, {
          'name'    => res[:action].str.downcase,
          'using'   => {
            'left'  =>  split_names(res[:joins][:lefts]),
            'right' => split_names(res[:joins][:rights]),
          },
          'include' => includes.inject({}) do |o, i|
            o.merge(i[:original].str => i.key?(:new) ? i[:new].str : i[:original].str)
          end
        })
      end

      def interpret_accumulate(o, res)
        act = {
          'name'     => res[:action].str.downcase,
          'column'   => res[:column].str,
          'function' => {
            'name' => res[:function][:name].str,
            'args' => split_names(res[:function][:args]),
          }
        }.tap do |a|
          a['result'] = res[:result].str if res.key?(:result)
        end
        add_action(o, act)
      end

      def add_action(o, act)
        o.merge('actions' => o.fetch('actions', []) << act)
      end

      def add_meta(o, section, d)
        meta = o.fetch('meta', {})
        sec = meta.fetch(section, {}).merge(d)
        meta = meta.merge(section => sec)
        o.merge('meta' => meta)
      end
      
      def parser
        @parser ||= ActionParser.new
      end
    end
  end
end
