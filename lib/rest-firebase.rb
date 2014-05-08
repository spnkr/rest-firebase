
require 'rest-core'

# https://www.firebase.com/docs/security/custom-login.html
# https://www.firebase.com/docs/rest-api.html
RestFirebase = RC::Builder.client(:d, :secret, :auth) do
  use RC::Timeout       , 10

  use RC::DefaultSite   , 'https://SampleChat.firebaseIO-demo.com/'
  use RC::DefaultHeaders, {'Accept' => 'application/json'}
  use RC::DefaultQuery  , nil

  use RC::FollowRedirect, 1
  use RC::CommonLogger  , nil
  use RC::Cache         , nil, 600 do
    use RC::ErrorHandler, lambda{ |env| RestFirebase::Error.call(env) }
    use RC::ErrorDetectorHttp
    use RC::JsonResponse, true
  end
end

class RestFirebase::Error < RestCore::Error
  include RestCore
  class ServerError         < RestFirebase::Error; end
  class ClientError         < RestCore::Error; end

  class BadRequest          < RestFirebase::Error; end
  class Unauthorized        < RestFirebase::Error; end
  class Forbidden           < RestFirebase::Error; end
  class NotFound            < RestFirebase::Error; end
  class NotAcceptable       < RestFirebase::Error; end
  class ExpectationFailed   < RestFirebase::Error; end

  class InternalServerError < RestFirebase::Error::ServerError; end
  class BadGateway          < RestFirebase::Error::ServerError; end
  class ServiceUnavailable  < RestFirebase::Error::ServerError; end

  attr_reader :error, :code, :url
  def initialize error, code, url=''
    @error, @code, @url = error, code, url
    super("[#{code}] #{error.inspect} from #{url}")
  end

  def self.call env
    error, code, url = env[RESPONSE_BODY], env[RESPONSE_STATUS],
                       env[REQUEST_URI]
    return new(error, code, url) unless error.kind_of?(Hash)
    case code
      when 400; BadRequest
      when 401; Unauthorized
      when 403; Forbidden
      when 404; NotFound
      when 406; NotAcceptable
      when 417; ExpectationFailed
      when 500; InternalServerError
      when 502; BadGateway
      when 503; ServiceUnavailable
      else    ; self
    end.new(error, code, url)
  end
end

module RestFirebase::Client
  include RestCore

  class EventSource < RestCore::EventSource
    def onmessage event=nil, data=nil, sock=nil
      if event
        super(event, Json.decode(data), sock)
      else
        super
      end
    end
  end

  def request env, app=app
    super(env.merge(REQUEST_PATH    => "#{env[REQUEST_PATH]}.json",
                    REQUEST_PAYLOAD => Json.encode(env[REQUEST_PAYLOAD])),
          app)
  end

  def generate_auth opts={}
    raise RestFirebase::Error::ClientError.new(
      "Please set your secret") unless secret

    header = {:typ => 'JWT', :alg => 'HS256'}
    claims = {:v => 0, :iat => Time.now.to_i, :d => d}.merge(opts)
    # http://tools.ietf.org/html/draft-ietf-jose-json-web-signature-26
    input = [header, claims].map{ |d| base64url(Json.encode(d)) }.join('.')
    # http://tools.ietf.org/html/draft-ietf-oauth-json-web-token-20
    "#{input}.#{base64url(Hmac.sha256(secret, input))}"
  end

  private
  def base64url str; [str].pack('m').tr('+/', '-_'); end
  def default_query; {:auth => auth}; end
  def default_auth ; generate_auth  ; end
end

class RestFirebase
  include RestFirebase::Client
  self.event_source_class = EventSource
end