require 'ffi'

module Event
  extend FFI::Library
  ffi_lib 'event'
  attach_function :event_init, [], :int
  attach_function :event_dispatch, [], :int
  attach_function :evbuffer_new, [], :pointer

  attach_function :evhttp_start, [:string, :int], :pointer
  callback :evhttp_callback, [:pointer, :pointer], :void
  attach_function :evhttp_set_gencb, [:pointer, :evhttp_callback, :pointer], :int

  attach_function :evbuffer_add_printf, [:pointer, :string], :int
  attach_function :evhttp_send_reply, [:pointer, :int, :string, :pointer], :int
  attach_function :evbuffer_free, [:pointer], :int
end


if $0 == __FILE__
  Event.event_init

  request_handler = Proc.new{|req, arg|
    buf = Event.evbuffer_new
    Event.evbuffer_add_printf(buf, "Thanks for the request!")
    Event.evhttp_send_reply(req, 200, "Client", buf)
    Event.evbuffer_free(buf)
  }

  http = Event.evhttp_start('127.0.0.1', 4500)
  Event.evhttp_set_gencb(http, request_handler, nil)

  Event.event_dispatch
end
