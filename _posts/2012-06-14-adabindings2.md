---
layout: post
title: Writing Ada Bindings for C Libraries, Part 2
tags: [ada, programming]
---

[Previously...][1]

### Types and Conventions

To declare C subprograms in Ada, you have to use parameter and return types that map
to the C types the subprogram uses. C's basic numeric types are available in Ada in
the package `Interfaces.C`. If the C code defines own types derived from the basic
C types, you should create a matching derived type in Ada. So if you have theses C
types:

{% highlight c %}
typedef int GLint;
typedef unsigned int GLuint;
typedef void GLvoid;
{% endhighlight %}

You can translate them to Ada like this:

{% highlight ada %}
type GLint is new Interfaces.C.int;
type GLuint is new Interfaces.C.unsigned;
type GLvoid is null record;
{% endhighlight %}

Note how C's `void` is mapped to Ada as `null record`. This isn't particularly
useful, I will discuss the handling of void pointers later.

In the following examples, `typedef` is used to define C types. These types
could also be anonymous types defined in the subprogram declaration. Even if
this is the case, you should still define the type explicitly in Ada to be able
to apply representation clauses or pragmas to it.

#### Structs

C structs are similar to Ada records. If you encounter a C struct, you can map it
to Ada with a record:

{% highlight c %}
typedef struct _cl_image_format {
   cl_channel_order image_channel_order;
   cl_channel_type  image_channel_data_type;
} cl_image_format;
{% endhighlight %}

{% highlight ada %}
type Image_Format is record
   Order     : Channel_Order;
   Data_Type : Channel_Type;
end record;
pragma Convention (C, Image_Format);
{% endhighlight %}

Note the usage of `pragma Convention` here. It tells the compiler to represent
the record in the way C represents a struct. However, be aware that the compiler
may still choose to use more space for representing the record than
`Channel_Order'Size + Channel_Type'Size`, particularly when the included types have a small
range (like e.g. Boolean). In cases where the Ada compiler chooses a different
representation for a record than the C compiler chooses for the struct, you have
to use a representation clause on the record.

#### Arrays

In C, arrays are mostly syntactic sugar for pointers, particularly when they
are used as parameters in subprogram declarations. C has no way of determining the
size of an array. Usually, a subprogram taking an array as parameter also takes
another parameter that gives the size of the array.

You will usually encounter C array types like this:

{% highlight c %}
typedef int *  int_array;
{% endhighlight %}

In Ada, this type looks like this:

{% highlight ada %}
type Int_Array is array (Integer range <>) of Interfaces.C.int;
pragma Convention (C, Int_Array);
for Int_Array'Component_Size use Interfaces.C.int'Size;
{% endhighlight %}

You should always use the Convention pragma. The following representation clause
is optional and may be needed in cases similar to those described in the structs
section above.

#### Enumerations

There are enumerations in C. You will probably not encounter them in their pure
form, but you will encounter a similar construct: A numeric parameter that takes
one of _n_ predefined constants as value. The C header may look like this:

{% highlight c %}
#define GL_ALPHA      0x1906
#define GL_LUMINANCE  0x1909
#define GL_INTENSITY  0x8049

typedef int depth_texture_mode;
{% endhighlight %}

While the type `depth_texture_mode` accepts any `int` value, a subprogram using
the type for a parameter will expect it to be one of the three values defined
above (the code doesn't tell you this, you have to look it up in the API
documentation).

In a case like this, you want to use an enumeration type in Ada:

{% highlight ada %}
type Depth_Mode is (Alpha, Luminance, Intensity);
for Depth_Mode use (Alpha     => 16#1906#,
                    Luminance => 16#1909#,
                    Intensity => 16#8049#);
for Depth_Mode'Size use Interfaces.C.int'Size;
{% endhighlight %}

Note that you cannot reference the numeric constants from the C header because
they are preprocessor macros. You have to copy-paste the values into Ada. It
is important to set the size for your type as the Ada compiler has no clue that
this type will be mapped to a C `int`.

#### Strings

In C, there are no strings. Well, not really. Whenever you want to have a string,
you actually use a `char` array that is terminated by a null character. This
special kind of array is available in Ada at `Interfaces.C.Strings`. It provides
conversions from and to an Ada `String`. Just use that package.

### Declaring the Subprograms in Ada

Now that we have defined the needed types in Ada, we need to translate the C
declarations to Ada.

#### By-value vs. By-reference

In C, subprogram parameters are always passed by-value, i.e. their contents is
copied into a local variable. In Ada, things are a bit more complex:

 * Basic types like Integer or Boolean are passed by-value. No problem here.
 * Composite types like records and arrays are passed by-reference. This means
   that a reference to their location is written into the parameter value. This
   is similar to using a pointer type in C. Keep this in mind when you're
   translating C declarations! It is not much of a problem with C arrays,
   because those are pointers anyway, but C structs can be passed by value. If
   you encounter a C subprogram that takes a struct as parameter, you need to
   use `pragma Convention (C_Pass_By_Copy, My_Type);` on your type.
 * If you define a parameter as `in out` in an Ada procedure declaration, it
   will also be passed by reference, so that the procedure can modify its value.

In C, when you want to have a by-reference parameter, you use a pointer type.

Using this knowledge, let's look at some C subprograms and their Ada
declarations:

{% highlight c %}
void proc1(int a, int *b, const int *c);
void proc2(depth_texture_mode mode, cl_image_format *format);
char *func1(void);
cl_image_format func2(size_t size, int_array some_ints);
{% endhighlight %}

{% highlight ada %}
procedure Proc1 (A : Interfaces.C.int;
                 B : in out Interfaces.C.int;
                 C : access constant Interfaces.C.int);
procedure Proc2 (Mode   : Depth_Mode;
                 Format : Image_Format);
function Func1 return Interfaces.C.Strings.chars_ptr;
function Func2 (Size      : Interfaces.C.size_t;
                Some_Ints : Int_Array) return Image_Format;
{% endhighlight %}

In **proc1**, parameter `A` is straightforward. Parameter `B` is an `int` pointer
in C, we map it as an `in out` parameter (we could also use an `access` parameter).
Parameter `C` is a constant pointer, and we map it as such.

In **proc2**, `mode` is just mapped as `Depth_Mode`, because enumeration types in
Ada are basic types and are passed by-value. The interesting part is the second
parameter `format`: It is defined as a pointer to the `cl_image_format` struct,
but we just use the record type `Image_Format`. We do this because the record
will be passed by-reference, thus conforming to the pointer type in C. Note that
we did not use `C_Pass_By_Copy` as Convention for `Image_Format`. If we did, we'd
have to define the parameter as `access Image_Format` (which works in both cases).

**func1** just returns a C string. We wrap it with Ada's `chars_ptr`.

In **func2**, we see how an array is passed to a C function. The first parameter
sets the size of the array, the second parameter is a pointer to the first array
element. In Ada, we can use the array type here because like above with the
record, the array is passed by-reference. If the array has the Convention `C`,
this is equivalent to passing a reference to the first array element.

Also note that the return value is always passed by-value, so we can use
`Image_Format` here without using `C_Pass_By_Copy`.

#### Import Statements

Import statements usually look like this:

{% highlight ada %}
pragma Import (Convention => C,
               Entity => Proc1,
               External_Name => "proc1");
{% endhighlight %}

In most cases, the convention is `C`. You may have noticed that I used `StdCall`
in my previous post. This is a convention used by the Windows API and some
third-party APIs like OpenGL. It is equivalent to the `C` convention on all
platforms except Windows.

If you overload the procedure `Proc1`, all entities with this name will be
imported as the specified C procedure.

This concludes the second part of this series. See you again when I cover some
advanced topics like handling void pointers and bitfields.

[To be continued...][2]

[1]: /2012/06/13/adabindings1/
[2]: /2013/02/18/adabindings3/