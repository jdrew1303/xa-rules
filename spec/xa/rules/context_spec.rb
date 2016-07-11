require 'xa/rules/context'
require 'xa/rules/rule'
require 'xa/registry/client'

describe XA::Rules::Context do
  it 'should execute a rule, in context' do
    r = instance_double(XA::Rules::Rule)
    ctx = XA::Rules::Context.new

    expect(r).to receive(:execute).with(ctx, {})
    expect(r).to receive(:repositories).and_yield(nil, nil)
    ctx.execute(r)
  end

  it 'should download from the registry' do
    expectations = [
      {
        url: 'http://foo.com',
        repo: 'foo',
        ns: 'foons',
        table: 'table_foo',
        version: '1234',
        type: :table,
        data: [
          { 'a' => '1', 'b' => '2' },
          { 'a' => '11', 'b' => '12' },
        ],
      },
      {
        url: 'http://faa.com',
        repo: 'baz',
        ns: 'bazns',
        table: 'table_baz',
        version: '111',
        type: :table,
        data: [
          { 'p' => '1', 'q' => '2' },
          { 'p' => '11', 'q' => '12' },
        ],
      },
    ]

    # context should be reusable
    ctx = XA::Rules::Context.new
    
    expectations.each do |ex|
      r = XA::Rules::Rule.new
      r.attach(ex[:url], ex[:repo])

      cl = instance_double(XA::Registry::Client)
      expect(XA::Registry::Client).to receive(:new).with(ex[:url]).and_return(cl)
      ctx.execute(r)

      expect(cl).to receive(:tables).with(ex[:ns], ex[:table], ex[:version]).and_return(ex[:data])
      ctx.get(ex[:type], { repo: ex[:repo], ns: ex[:ns], table: ex[:table], version: ex[:version] }) do |actual|
        expect(actual).to eql(ex[:data])
      end
    end
  end
end
