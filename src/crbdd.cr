require "big"
require "./crbdd/*"

# Reduced ordered binary decision diagrams.
#
# ```
# m = CrBDD::Manager.new(%w[a b c])
# f = (m.var("a") & m.var("b")) | m.var("c")
# f.satcount # => 5
# ```
module CrBDD
  VERSION = "0.1.0"

  class Error < Exception; end
end
