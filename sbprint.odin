
package fourth

import "core:strings"
import "core:fmt"

sbprint :: proc(node: ^Link, b: ^strings.Builder, prefix := "") {
    
    if leaf := node_cast(Leaf, node); leaf != nil {
        fmt.sbprintf(b, "[%v %s]\n", leaf.token.kind, leaf.token.text)
        return
    }
    
    if cont := node_cast(Continue, node); cont != nil {
        fmt.sbprintf(b, "continue\n")
        return
    }

    if brk := node_cast(Break, node); brk != nil {
        fmt.sbprintf(b, "break\n")
        return
    }
    
    if decl := node_cast(Decl, node) ; decl != nil {
        if decl.forward {
            fmt.sbprintf(b, "forward %s\n", decl.name.text)
        } else {
            fmt.sbprintf(b, "decl %s\n", decl.name.text)
        }
        if decl.rhs != nil {
            fmt.sbprintf(b, "%s%s", prefix, "└───")
            next_prefix := strings.join({prefix, "    "},"")
            sbprint(decl.rhs, b, next_prefix)
            delete(next_prefix)
        }
        return
    }

    if ret := node_cast(Return, node); ret != nil {
        fmt.sbprintf(b, "return\n")
        if ret.result != nil {
            fmt.sbprintf(b, "%s%s", prefix, "└───")
            next_prefix := strings.join({prefix, "    "},"")
            sbprint(ret.result, b, next_prefix)
            delete(next_prefix)
        }
        return
    }

    if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
        fmt.sbprintf(b, "[%v `%s`]\n", unary_expr.kind, unary_expr.op_token.text)

        fmt.sbprintf(b, "%s%s", prefix, "└───")
        next_prefix := strings.join({prefix, "    "},"")
        sbprint(unary_expr.operand, b, next_prefix)
        delete(next_prefix)
        return
    }

    if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
        fmt.sbprintf(b, "[%v `%s`]\n", bin_expr.kind, bin_expr.op_token.text)

        fmt.sbprintf(b, "%s%s", prefix, "├───")
        next_prefix1 := strings.join({prefix, "│   "},"")
        sbprint(bin_expr.left, b, next_prefix1)
        delete(next_prefix1)

        fmt.sbprintf(b, "%s%s", prefix, "└───")
        next_prefix2 := strings.join({prefix, "    "},"")
        sbprint(bin_expr.right, b, next_prefix2)
        delete(next_prefix2)
        return
    }
    
    if block := node_cast(Block, node); block != nil {
        fmt.sbprintf(b, "do\n")
        for node, i in block.code {
            is_last := i == len(block.code) - 1
            next_prefix: string
         if !is_last {
                fmt.sbprintf(b, "%s%s", prefix, "├───")
                next_prefix = strings.join({prefix, "│   "},"")
            } else {
                fmt.sbprintf(b, "%s%s", prefix, "└───")
                next_prefix = strings.join({prefix, "    "},"")
            }
            sbprint(node, b, next_prefix)
            delete(next_prefix)
        }
        return
    }
    
    if list := node_cast(Param_List, node); list != nil {
        fmt.sbprintf(b, "param_list\n")
        for node, i in list.params {
            is_last := i == len(list.params) - 1
            next_prefix: string
            if !is_last {
                fmt.sbprintf(b, "%s%s", prefix, "├───")
                next_prefix = strings.join({prefix, "│   "},"")
            } else {
                fmt.sbprintf(b, "%s%s", prefix, "└───")
                next_prefix = strings.join({prefix, "    "},"")
            }
            if node == nil {
                fmt.sbprintf(b, "default\n")
            } else {
                sbprint(node, b, next_prefix)
            }
            delete(next_prefix)
        }
        return
    }
    
    if while := node_cast(While, node); while != nil {
        fmt.sbprintf(b, "while\n")
        fmt.sbprintf(b, "%s%s", prefix, "├───")
        next_prefix1 := strings.join({prefix, "│   "},"")
        sbprint(while.cond, b, next_prefix1)
        delete(next_prefix1)

        fmt.sbprintf(b, "%sloop\n", prefix)
        fmt.sbprintf(b, "%s%s", prefix, "└───")
        next_prefix2 := strings.join({prefix, "    "},"")
        sbprint(while.body, b, next_prefix2)
        delete(next_prefix2)
        return
    }

    // THE EPITOME OF `DRY` PROGRAMMING!
    if if_else := node_cast(If_Else, node); if_else != nil {
        fmt.sbprintf(b, "if\n")
        fmt.sbprintf(b, "%s%s", prefix, "├───")
        next_prefix1 := strings.join({prefix, "│   "},"")
        sbprint(if_else.cond, b, next_prefix1)
        delete(next_prefix1)

        if if_else.else_body != nil {
            fmt.sbprintf(b, "%sthen\n", prefix)
            fmt.sbprintf(b, "%s%s", prefix, "├───")
            next_prefix2 := strings.join({prefix, "│   "},"")
            sbprint(if_else.if_body, b, next_prefix2)
            delete(next_prefix2)

            fmt.sbprintf(b, "%selse\n", prefix)
            fmt.sbprintf(b, "%s%s", prefix, "└───")
            next_prefix3 := strings.join({prefix, "    "},"")
            sbprint(if_else.else_body, b, next_prefix3)
            delete(next_prefix3)
        } else {
            fmt.sbprintf(b, "%sthen\n", prefix)
            fmt.sbprintf(b, "%s%s", prefix, "└───")
            next_prefix2 := strings.join({prefix, "    "},"")
            sbprint(if_else.if_body, b, next_prefix2)
            delete(next_prefix2)
        }
        return
    }
    
    if func := node_cast(Function, node) ; func != nil {
        fmt.sbprintf(b, "function\n")
        
        if len(func.params) == 0 {
            fmt.sbprintf(b, "%s├───none\n", prefix)
        } else {
            for node, i in func.params {
                fmt.sbprintf(b, "%s%s", prefix, "├───")
                next_prefix := strings.join({prefix, "│   "},"")
                sbprint(node, b, next_prefix)
                delete(next_prefix)
            }
        }

        fmt.sbprintf(b, "%sbody\n", prefix)
        fmt.sbprintf(b, "%s%s", prefix, "└───")
        next_prefix := strings.join({prefix, "    "},"")
        sbprint(func.body, b, next_prefix)
        delete(next_prefix)
        return
    }

    fmt.printf("%v\n", node.kind)
    assert(false, "unknown AST_Kind in `sbprint`")
}

