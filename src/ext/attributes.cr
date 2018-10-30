# While waiting for https://github.com/crystal-lang/crystal/pull/6910 to hit master
struct XML::Attributes
  def delete(name : String)
    value = self[name]?.try &.content
    res = LibXML.xmlUnsetProp(@node, name)
    value if res == 0
  end
end
