
require 'rest-firebase'
require 'rest-builder/test'

Pork.protected_exceptions << WebMock::NetConnectNotAllowedError

Pork::API.describe RestFirebase do
  before do
    stub_select_for_stringio
    stub(Time).now{ Time.at(86400) }
  end

  after do
    WebMock.reset!
    Muack.verify
  end

  path = 'https://a.json?auth=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ2IjowLCJpYXQiOjg2NDAwLCJkIjpudWxsfQ%3D%3D.SSmw2fUYiQFyYlsFV8WmyQsOCWJ6yvC7aw3bRpwQOYo%3D'

  json = '{"status":"ok"}'
  rbon = {'status' => 'ok'}

  def firebase
    @firebase ||= RestFirebase.new(:secret => 'nnf')
  end

  would 'get true' do
    stub_request(:get, path).to_return(:body => 'true')
    firebase.get('https://a').should.eq true
  end

  would 'get true with callback' do
    stub_request(:get, path).to_return(:body => 'true')
    firebase.get('https://a') do |r|
      r.should.eq true
    end.wait
  end

  would 'get with query' do
    stub_request(:get, "#{path}&orderBy=%22date%22&limitToFirst=1").
      to_return(:body => json)
    firebase.get('https://a', :orderBy => 'date', :limitToFirst => 1).
      should.eq rbon
  end

  would 'put {"status":"ok"}' do
    stub_request(:put, path).with(:body => json).to_return(:body => json)
    firebase.put('https://a', rbon).should.eq rbon
  end

  would 'have no payload for delete' do
    stub_request(:delete, path).with(:body => nil).to_return(:body => json)
    firebase.delete('https://a').should.eq rbon
  end

  would 'parse event source' do
    stub_request(:get, path).to_return(:body => <<-SSE)
event: put
data: {}

event: keep-alive
data: null

event: invalid
data: invalid
SSE
    m = [{'event' => 'put'       , 'data' => {}},
         {'event' => 'keep-alive', 'data' => nil}]
    es = firebase.event_source('https://a')
    es.should.kind_of? RestFirebase::Client::EventSource
    es.onmessage do |event, data|
      {'event' => event, 'data' => data}.should.eq m.shift
    end.onerror do |error|
      error.should.kind_of? RC::Json::ParseError
    end.start.wait
    m.should.empty?
  end

  would 'refresh token' do
    firebase # initialize http-client first (it's using Time.now too)
    mock(Time).now{ Time.at(0) }
    auth, query = firebase.auth, firebase.query
    query[:auth].should.eq auth
    Muack.verify(Time)
    stub(Time).now{ Time.at(86400) }

    stub_request(:get, path).to_return(:body => 'true')
    firebase.get('https://a').should.eq true
    firebase.auth .should.not.eq auth
    firebase.query.should.not.eq query
  end

  would 'not double encode json upon retrying' do
    stub_request(:post, path).
      to_return(:body => '{}', :status => 500).times(1).then.
      to_return(:body => '[]', :status => 200).times(1).
        with(:body => '{"is":"ok"}')

    firebase.retry_exceptions = [TrueClass]
    firebase.max_retries      = 1
    firebase.error_handler    = false
    expect(firebase.post(path, :is => :ok)).eq([])
  end

  define_method :check do |status, klass|
    stub_request(:delete, path).to_return(
      :body => '{}', :status => status)

    lambda{ firebase.delete('https://a').tap{} }.should.raise(klass)

    WebMock.reset!
  end

  would 'raise exception when encountering error' do
    [400, 401, 402, 403, 404, 406, 417].each do |status|
      check(status, RestFirebase::Error)
    end
    [500, 502, 503].each do |status|
      check(status, RestFirebase::Error::ServerError)
    end
  end
end
