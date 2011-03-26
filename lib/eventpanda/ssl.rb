require 'ffi'

module EventPanda

  # libevent_openssl requires a symbol from libevent_core. tell ffi to load them as global.
  def self.ffi_lib_global(*names)
    @ffi_lib_flags = FFI::DynamicLibrary::RTLD_LAZY | FFI::DynamicLibrary::RTLD_GLOBAL
    ffi_lib(*names)
    @ffi_lib_flags = nil
  end
  ffi_lib_global 'event_core', 'event_openssl'
  attach_function :bufferevent_openssl_socket_new, [:pointer, :uint, :pointer, :uint, :uint], :pointer
  attach_function :bufferevent_openssl_filter_new, [:pointer, :pointer, :pointer, :uint, :uint], :pointer


  module SSL
    extend FFI::Library
    ffi_lib 'ssl'

    attach_function :SSL_library_init, [], :int
    attach_function :ERR_load_crypto_strings, [], :void
    attach_function :SSL_load_error_strings, [], :void
    attach_function :RAND_poll, [], :int
    attach_function :SSLv23_server_method, [], :pointer
    attach_function :SSL_CTX_new, [:pointer], :pointer
    attach_function :SSL_new, [:pointer], :pointer
    attach_function :SSL_use_certificate_file, [:pointer, :string, :int], :int
    attach_function :SSL_use_PrivateKey_file, [:pointer, :string, :int], :int

    SSL_FILETYPE_PEM = 1
    SSL_VERIFY_NONE = 0
    SSL_VERIFY_PEER = 1
    SSL_VERIFY_FAIL_IF_NO_PEER_CERT = 2

    def self.init
      return if Thread.current[:ssl_ctx]
      SSL.SSL_library_init
      SSL.ERR_load_crypto_strings
      SSL.SSL_load_error_strings
      #p SSL.OpenSSL_add_all_algorithms
      SSL.RAND_poll

      Thread.current[:ssl_ctx] = SSL.SSL_CTX_new(SSL.SSLv23_server_method)
    end

    def self.get_ctx; Thread.current[:ssl_ctx] ||= (init; SSL_CTX_new(SSLv23_server_method())); end

    # ssl methods for EventPanda::Connection
    module ConnectionMethods
      def start_tls(opts={})
        if opts[:private_key_file] && opts[:cert_chain_file]
          ssl = SSL.SSL_new(EventPanda::SSL.get_ctx)
          raise "ssl error (SSL_new pointer is null)" if ssl.null?

          SSL.SSL_use_certificate_file(ssl, opts[:cert_chain_file], SSL::SSL_FILETYPE_PEM)
          SSL.SSL_use_PrivateKey_file(ssl, opts[:private_key_file], SSL::SSL_FILETYPE_PEM)

          EventPanda.bufferevent_disable(@bev)
          @bev_plain = @bev

          @bev = EventPanda.bufferevent_openssl_filter_new(Thread.current[:ev_base], @bev_plain, ssl,
            EventPanda::BUFFEREVENT_SSL_ACCEPTING, EventPanda::BEV_OPT_CLOSE_ON_FREE|EventPanda::BEV_OPT_DEFER_CALLBACKS)
          init_bev # re-assign @bev_*

          @use_ssl = true

        elsif opts[:verify_peer] == true
          # ..
        end
      end

      def ssl_verify(cert)
        p cert
      end
    end

  end
end
