# Eventpanda

eventpanda is an API compatible drop-in replacement for EventMachine using FFI and libevent2 instead of the C++ reactor.

## Notes

Still in beta, but it works. please report any issues :)

## Examples

### Thin / Rack

    # runs a rack-app on thin using eventpanda instead of eventmachine as its backend.
    cd eventpanda
    ruby -Ilib -reventpanda/em/eventmachine -rrack -e "app = Rack::Directory.new('.');  Rack::Handler::Thin.run(app)"


## Installation

    git clone https://github.com/lian/eventpanda.git

No compilation is required. You must have libevent >= 2.0 installed.


## License

License can be found in the file COPYING.

