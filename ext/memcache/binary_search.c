#include "ruby.h"
#include "stdio.h"

/*
def binary_search(ary, value)
  upper = ary.size - 1
  lower = 0
  idx = 0

  while(lower <= upper) do
    idx = (lower + upper) / 2
    comp = ary[idx].value <=> value

    if comp == 0
      return idx
    elsif comp > 0
      upper = idx - 1
    else
      lower = idx + 1
    end
  end
  return upper
end
*/ 
static VALUE binary_search(VALUE self, VALUE ary, VALUE number) {
    int upper = RARRAY_LEN(ary) - 1;
    int lower = 0;
    int idx = 0;
    unsigned int r = NUM2UINT(number);
    ID value = rb_intern("value");
    
    while (lower <= upper) {
        idx = (lower + upper) / 2;
        
        VALUE continuumValue = rb_funcall(RARRAY_PTR(ary)[idx], value, 0);
        unsigned int l = NUM2UINT(continuumValue);
        if (l == r) {
            return INT2FIX(idx);
        }
        else if (l > r) {
            upper = idx - 1;
        }
        else {
            lower = idx + 1;
        }
    }
    return INT2FIX(upper);
}
 
VALUE cContinuum;
void Init_binary_search() {
  cContinuum = rb_define_module("Continuum");
  rb_define_module_function(cContinuum, "binary_search", binary_search, 2);
}