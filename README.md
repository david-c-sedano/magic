
# THE MAGIC PROGRAMMING LANGUAGE
This is my custom programming language/compiler. Currently work in progress.

# TODO:
Code generation is finished! The gap between a usable, polished language and I what I currently have, though, is massive! 

1. document
2. better codegen "error" messages (fault system)
3. tester

# DOCUMENTATION?
need to rewrite the spec, `invoke` and `stride_of` are crazy features.

## what does `stride_of` do?
It's like compile-time reflection but for cavemen. It returns the size of a layout attached to a pointer from an expression. So it's like `size_of` but `size_of` strictly takes another identifier and not an expression. 

```
layout Vector2
    x: f32
    y: f32

decl vec = push Vector2
stride_of vec // equal to 8
```

If the expression in `stride_of` wouldn't evaluate to a ptr with layout, then it's an error. You can probably use this to write generic hash tables or some sheet IDK
