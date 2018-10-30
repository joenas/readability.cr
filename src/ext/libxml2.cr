# While waiting for https://github.com/crystal-lang/crystal/pull/6910 to hit master
lib LibXML
  fun xmlUnsetProp(node : Node*, name : UInt8*) : Int
end
