require 'ffi'
require 'socket'

module EventPanda
module Libevent
  extend FFI::Library
  ffi_lib 'event_core'

  # event base loop
  attach_function :event_base_new, [], :pointer
  attach_function :event_base_free, [:pointer], :void
  attach_function :event_base_get_method, [:pointer], :string
  #attach_function :event_init, [], :int
  #attach_function :event_dispatch, [], :int
  attach_function :event_base_dispatch, [:pointer], :int
  attach_function :event_base_loop, [:pointer, :int], :int
  attach_function :event_base_loopexit, [:pointer, :pointer], :int
  attach_function :event_base_loopbreak, [:pointer], :int

  # events/timers
  callback :event_callback, [:pointer, :pointer], :void
  attach_function :event_new, [:pointer, :int, :short, :event_callback], :pointer
  attach_function :event_add, [:pointer, :pointer], :int
  attach_function :event_assign, [:pointer, :pointer, :int, :int, :event_callback], :pointer
  attach_function :event_del, [:pointer], :int
  attach_function :event_free, [:pointer], :int

  # evbuffers
  attach_function :evbuffer_new, [], :pointer
  attach_function :evbuffer_free, [:pointer], :int
  attach_function :evbuffer_add_printf, [:pointer, :string], :int
  attach_function :evbuffer_add_buffer, [:pointer, :pointer], :int
  attach_function :evbuffer_readline, [:pointer], :string

  # start server
  callback :accept_error_cb, [:pointer, :pointer], :void
  callback :accept_connection_cb, [:pointer, :uint, :pointer, :int, :pointer], :void
  attach_function :evconnlistener_set_error_cb, [:pointer, :accept_error_cb], :int
  attach_function :evconnlistener_new_bind, [:pointer, :accept_connection_cb, :pointer, :uint, :int, :pointer, :int], :pointer
  attach_function :evconnlistener_free, [:pointer], :void
  attach_function :evconnlistener_enable, [:pointer], :int
  attach_function :evconnlistener_disable, [:pointer], :int

  # new connection
  attach_function :evconnlistener_get_base, [:pointer], :pointer
  attach_function :bufferevent_socket_new, [:pointer, :uint, :int], :pointer

  # connection callbacks
  callback :bev_data_cb,  [:pointer, :pointer], :void
  callback :bev_event_cb, [:pointer, :short, :pointer], :void
  attach_function :bufferevent_setcb, [:pointer, :bev_data_cb, :bev_data_cb, :bev_event_cb, :pointer], :void
  attach_function :bufferevent_enable, [:pointer, :short], :int
  attach_function :bufferevent_disable, [:pointer], :int
  attach_function :bufferevent_get_input, [:pointer], :pointer
  attach_function :bufferevent_get_output, [:pointer], :pointer

  # evhttp (disabled for now)
  #attach_function :evhttp_start, [:string, :int], :pointer
  #callback :evhttp_callback, [:pointer, :pointer], :void
  #attach_function :evhttp_set_gencb, [:pointer, :evhttp_callback, :pointer], :int
  #attach_function :evhttp_send_reply, [:pointer, :int, :string, :pointer], :int

  attach_function :evbuffer_write, [:pointer, :uint], :int
  attach_function :evbuffer_write_atmost, [:pointer, :uint, :uint], :int
  attach_function :evbuffer_read, [:pointer, :uint, :int], :int
  attach_function :evbuffer_get_length, [:pointer], :int

  attach_function :bufferevent_read, [:pointer, :pointer, :uint], :int
  attach_function :bufferevent_write, [:pointer, :pointer, :uint], :int

  attach_function :bufferevent_socket_connect, [:pointer, :pointer, :uint], :int
  attach_function :event_get_fd, [:pointer], :int
  attach_function :bufferevent_getfd, [:pointer], :int
  attach_function :bufferevent_free, [:pointer], :int

  attach_function :bufferevent_set_timeouts, [:pointer, :pointer, :pointer], :void
  attach_function :bufferevent_flush, [:pointer, :short, :int], :int
  BEV_FLUSH = 1
  BEV_FINISHED = 2

  EVLOOP_ONCE     = 1
  EVLOOP_NONBLOCK = 2

  BUFFEREVENT_SSL_ACCEPTING = 2
  BEV_OPT_DEFER_CALLBACKS = 4

  LEV_OPT_CLOSE_ON_FREE = 2
  LEV_OPT_REUSEABLE     = 8
  BEV_OPT_CLOSE_ON_FREE = 1
  EV_TIMEOUT = 1
  EV_READ = 2
  EV_WRITE = 4
  EV_PERSIST = 10
end
end
