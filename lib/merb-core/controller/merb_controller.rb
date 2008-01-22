class Merb::Controller < Merb::AbstractController
  
  class_inheritable_accessor :_session_id_key, :_session_expiry, :_hidden_actions
  cattr_accessor :_subclasses, :_session_secret_key
  self._subclasses = Set.new
  def self.subclasses_list() _subclasses end
  
  self._session_secret_key = nil
  self._session_id_key = '_session_id'
  self._session_expiry = Time.now + Merb::Const::WEEK * 2
  
  include Merb::ResponderMixin
  include Merb::Hook
  
  class << self
    
    # ==== Parameters
    # klass<Merb::Controller>:: The Merb::Controller inheriting from the
    #                           base class
    def inherited(klass)
      _subclasses << klass.to_s
      super
    end

    # Hide each of the given methods from being callable as actions.
    #
    # ==== Parameters
    # *names<~to-s>:: Actions that should be added to the list 
    #
    # ==== Returns
    # Array<String::
    #   An array of actions that should not be possible to dispatch to
    # 
    #---
    # @public
    def hide_action(*names)
      self._hidden_actions = self._hidden_actions | names.map { |n| n.to_s }
    end

    def _hidden_actions
      actions = read_inheritable_attribute(:_hidden_actions)
      actions ? actions : write_inheritable_attribute(:_hidden_actions, [])
    end

    def callable_actions
      @callable_actions ||= Merb::SimpleSet.new((public_instance_methods - _hidden_actions).map {|x| x.to_s})
    end
    
    # Build a new controller.
    #
    # ==== Parameters
    # request<Merb::Request>:: The Merb::Request that came in from Mongrel
    # response<IO>:: 
    #   The response IO object to write the response to. This could be any
    #   IO object, but is probably an HTTPResponse
    # status<Integer>:: An integer code for the status
    # headers<Hash{header => value}>:: 
    #   A hash of headers to start the controller with. These headers
    #   can be overridden later by the #headers method
    #
    # ==== Returns
    # Merb::Controller::
    #   The Merb::Controller that was built from the parameters
    # 
    #---
    # @semipublic
    def build(request, response = StringIO.new, status=200, headers={'Content-Type' => 'text/html; charset=utf-8'})
      cont = new
      cont.set_dispatch_variables(request, response, status, headers)
      cont
    end
  end
  
  def _template_location(action, type = nil, controller = controller_name)
    "#{controller}/#{action}.#{type}"
  end  
  
  # Sets the variables that came in through the dispatch as available to
  # the controller. This is called by .build, so see it for more
  # information.
  #
  # This method uses the :session_id_cookie_only and :query_string_whitelist
  # configuration options. See CONFIG for more details.
  #
  # ==== Parameters
  # request<Merb::Request>:: The Merb::Request that came in from Mongrel
  # response<IO>:: 
  #   The response IO object to write the response to. This could be any
  #   IO object, but is probably an HTTPResponse
  # status<Integer>:: An integer code for the status
  # headers<Hash{header => value}>:: 
  #   A hash of headers to start the controller with. These headers
  #   can be overridden later by the #headers method
  #
  # ==== Returns
  # nil
  def set_dispatch_variables(request, response, status, headers)
    if request.params.key?(_session_id_key)
      if Merb::Config[:session_id_cookie_only]
        # This condition allows for certain controller/action paths to allow
        # a session ID to be passed in a query string. This is needed for
        # Flash Uploads to work since flash will not pass a Session Cookie
        # Recommend running session.regenerate after any controller taking
        # advantage of this in case someone is attempting a session fixation
        # attack
        if Merb::Config[:query_string_whitelist].include?("#{request.controller_name}/#{request.action}")
        # FIXME to use routes not controller and action names -----^
          request.cookies[_session_id_key] = request.params[_session_id_key]
        end
      else
        request.cookies[_session_id_key] = request.params[_session_id_key]
      end
    end
    @request, @response, @status, @headers = request, response, status, headers
    nil
  end
  
  # Dispatch the action
  #
  # ==== Parameters
  # action<~to_s>:: An action to dispatch to
  #
  # ==== Returns
  # String:: The string sent to the logger for time spent
  # 
  #---
  # @semipublic
  def _dispatch(action=:index)
    start = Time.now
    if self.class.callable_actions.include?(action.to_s)
      hook :before_dispatch
      super(action)
      hook :after_dispatch
    else
      raise ActionNotFound, "Action '#{action}' was not found in #{self.class}"
    end
    @_benchmarks[:action_time] = Time.now - start
  end
  
  attr_reader :request, :response, :headers
  attr_accessor :status
  def params()  request.params  end
  def cookies() request.cookies end
  def session() request.session end
  def route()   request.route   end
end