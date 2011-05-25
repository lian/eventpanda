# skip original require 'eventmachine'
# USAGE: ruby -reventpanda/em/eventmachine  [..]

skip_path = File.expand_path(File.join(File.dirname(__FILE__)))

unless $:.include? skip_path
  $:.unshift skip_path
  require 'eventmachine' # false already.. see below.
  require 'eventpanda'
else
  # never happens.. __FILE__ is named 'eventmachine'
  # and already required once.
  raise 'skip eventmachine required twice!'
end
