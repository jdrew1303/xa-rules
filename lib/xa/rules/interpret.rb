require_relative './rule'

module XA
  module Rules
    module Interpret
      def interpret(o)
        r = XA::Rules::Rule.new
        interpret_meta(o.fetch('meta', {}), r)
        interpret_actions(o.fetch('actions', []), r)
        r
      end

      private

      ACTIONS = [
        'push',
        'pop',
        'duplicate',
        'join',
        'inclusion',
        'commit',
        'accumulate',
        'pull',
      ]
      
      def interpret_meta(meta, r)
        meta.fetch('expects', {}).each do |args|
          r.expects(*args)
        end
        meta.fetch('repositories', {}).each do |name, url|
          r.attach(url, name)
        end
      end

      def interpret_actions(actions, r)
        actions.each do |c|
          interpretation(c.fetch('name', nil)) do |fn|
            fn.call(r, c)
          end
        end
      end

      def interpret_push(r, c)
        r.push(c['table'])
      end

      def interpret_pop(r, c)
        r.pop
      end

      def interpret_duplicate(r, c)
        r.duplicate
      end
      
      def interpret_commit(r, c)
        r.commit(c['table'], c.fetch('columns', nil))
      end
      
      def interpret_join(r, c)
        interpret_joinish(:join, r, c)
      end

      def interpret_inclusion(r, c)
        interpret_joinish(:inclusion, r, c)
      end

      def interpret_joinish(action, r, c)
        r.send(action).using(c['using']['left'], c['using']['right']).include(c['include'])
      end

      def interpret_accumulate(r, c)
        r.accumulate(c['column'], c['result']).apply(c['function']['name'], c['function']['args'])
      end

      def interpret_pull(r, c)
        r.pull(c['as'], c['namespace'], c['table'], c['version'])
      end
      
      def interpret_unknown(r, c)
      end
      
      def interpretation(t)
        @interpretations ||= ACTIONS.inject({}) do |o, t|
          o.merge(t => method("interpret_#{t}"))
        end
        
        yield(@interpretations.fetch(t, method(:interpret_unknown)))
      end
    end
  end
end
