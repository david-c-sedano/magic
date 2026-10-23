
# THE MAGIC PROGRAMMING LANGUAGE
This is my custom programming language/compiler. Currently work in progress.

# TODO:
Code generation is finished! The gap between a usable, polished language and I what I currently have, though, is massive! 

1. start writing stdlib
2. figure out how to return """"structs"""" (not really structs)
3. figure out subscripting
4. better codegen "error" messages (more like developer embarassment)
5. write more tests/examples!

# note about `invoke`
I need to add this to the spec. This kind of a huge feature.

I am going to hate myself trying to observe what my program does by shoehorning in a bunch of hacks with the tags (like `@exit` or `@puts`) so I will begin with C interop because this is the sad state of computers atm

somthing like `extern` makes little sense to me because function calls in Magic are very abstract and inferential. What makes more sense is something like
```
layout _rlArgs__InitWindow
    width: s32
    height: s32
    title: ptr

forward InitWindow = def(width, height, title) do 
    decl args = push _rlArgs__InitWindow
    args.width = width
    args.height = height
    args.title = title
    invoke:InitWindow args
```
if you want return values you'd need to supply a cast 
```
layout _libcArgs__Malloc
    size: u64

forward malloc = def(size) do
    decl args = push _libcArgs__Malloc
    args.size = size
    return invoke:malloc args as ptr
```
Then I can begin development of my highly realistic, 3d rendered, open-world, MMORPG game with tactical combat to ship on PC, XBOX, and the Nintendo 64

