using CSTParser
using CSTParser: EXPR, Call, Location, expr_location, charrange

expridx(x, ii) = (@assert isempty(ii); x)
expridx(x::Expr, ii) = isempty(ii) ? x : expridx(x.args[ii[1]], ii[2:end])

function precedence_level(cst::EXPR, loc::Location)
  parent = cst[CSTParser.parent(loc)]
  if parent isa Union{CSTParser.BinaryOpCall,CSTParser.UnaryOpCall,CSTParser.ChainOpCall}
    Base.operator_precedence(Expr(parent).args[1])
  elseif parent isa Union{CSTParser.BinarySyntaxOpCall,CSTParser.UnarySyntaxOpCall}
    Base.operator_precedence(Expr(parent).head)
  else
    0
  end
end

separator(x::EXPR{Call}, i::Integer) = max(i-1, 4)

function separator(cst::EXPR, loc::Location)
  parent = CSTParser.parent(loc)
  i = separator(cst[parent], loc.ii[end])
  CSTParser.child(parent, i)
end

struct SourceFile
  path::String
  text::String
  cst::EXPR
  ast::Expr
end

function SourceFile(path::String, text = String(read(path)))
  cst = CSTParser.parse(text, true)
  SourceFile(path, text, cst, Expr(cst))
end

function replacement(src::SourceFile, p::Replace)
  loc = expr_location(src.cst, p.idx)
  prec = precedence_level(src.cst, loc)
  _, span = charrange(src.cst, loc)
  span => sprint(Base.show_unquoted, p.new, 0, prec)
end

function replacement(src::SourceFile, p::Insert)
  append = p.idx[end] > length(expridx(src.ast, p.idx[1:end-1]).args)
  append && (p.idx[end] -= 1)
  loc = expr_location(src.cst, p.idx)
  span, _ = charrange(src.cst, loc)
  point = append ? span[end] : span[1]-1
  sep = charrange(src.cst, separator(src.cst, loc))[1]
  (1:0).+point => sprint() do io
    append && write(io, src.text[sep])
    Base.show_unquoted(io, p.tree, 0, 0)
    append || write(io, src.text[sep])
  end
end

replacement(src::SourceFile, p::Patch) = [replacement(src, p) for p in p.ps]

function patch(io::IO, src::SourceFile, rs)
  rs = sort(rs, by=x->first(x[1]))
  offset = 1
  for r in rs
    print(io, src.text[(offset:first(r[1])-1)])
    print(io, r[2])
    offset = last(r[1])+1
  end
  print(io, src.text[offset:end])
end

patch(io::IO, src::SourceFile, p::Patch) = patch(io, src, replacement(src, p))

patch(src::SourceFile, p) = sprint(patch, src, p)

function patch!(src::SourceFile, p)
  open(src.path, "w") do io
    patch(io, src, p)
  end
end

function sourcemap(f, src::SourceFile)
  ex = striplines(f(src.ast))
  patch(src, diff(src.ast, ex))
end

# TODO directories
function sourcemap(f, path::AbstractString)
  isfile(path) || error("No file at $f")
  s = SourceFile(path)
  ex = striplines(f(s.ast))
  patch!(s, diff(s.ast, ex))
end

sourcewalk(f, file) = sourcemap(x -> postwalk(f, x), file)

textwalk(f, text) = sourcewalk(f, SourceFile("", text))