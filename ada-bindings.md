---
layout: default
title: Writing Ada Bindings for C Libraries
title_short: Ada to C Bindings
kind: article
permalink: /ada-bindings/
weight: 2
date: 2012-06-13
---

This article gives an overview over problems, solutions and guidelines for writing an
Ada binding for a C library. It summarizes experiences I made while implementing
[OpenCLAda][1] and [OpenGLAda][2]. Code examples are taken from those projects.

The Ada code examples shown here are written in Ada 2005. Note that you can import C
functions somewhat nicer in Ada 2012.

## Thin or Thick?

There are two kinds of bindings: _Thin_ and _thick_ ones. A _thin_ binding usually just
provides Ada declarations for the C subprograms, while the _thick_ binding may provide
some code that marshals between the C subprogram and the public Ada API you want to
provide with your binding. Let's have an example, consider this C declaration:

{% highlight c %}
extern CL_API_ENTRY cl_int CL_API_CALL
clGetDeviceIDs(cl_platform_id   /* platform */,
               cl_device_type   /* device_type */,
               cl_uint          /* num_entries */,
               cl_device_id *   /* devices */,
               cl_uint *        /* num_devices */)
    CL_API_SUFFIX__VERSION_1_0;
{% endhighlight %}

This is a typical C subprogram that lets you query a variant number of values (in this
case, OpenCL device IDs). You provide an array in which the values should be written
(`devices`), tell the API the length of your array (`num_entries`) and get back the
number of values that has been written in your array (`num_devices`). The return value
is an error code.

A thin wrapper for this function looks like this:

{% highlight ada %}
function Get_Device_IDs (Source      : Platform_Id;
                         Types       : Device_Type;
                         Num_Entries : UInt;
                         Devices     : access Device_Id;
                         Num_Devices : access UInt)
                         return Int;
pragma Import (Convention => StdCall, Entity => Get_Device_IDs,
               External_Name => "clGetDeviceIDs");
{% endhighlight %}

As we see, the caller needs to have exactly the same knowledge to use this Ada function
as he needs to use the C API. Now compare a possible API of a thick binding:

{% highlight ada %}
function Devices (Source : Platform; Types : Device_Kind)
                 return Device_List;
{% endhighlight %}

The differences are:

 * The thick binding hides the low-level issues with C arrays. You do not need to
   provide an array which will be filled and returned to you. Instead, the function
   returns a newly created array that contains the values you requested.
 * This is not a direct import. The thick binding has an implementation in Ada which
   calls the C library and marshals the return values to the Ada API.
 * The error code is gone. The implementation will raise an exception when an error
   occurs.

Of course, the thick binding still needs to declare the C function in Ada. So a thick
binding is basically an Add-On to a thin binding which changes the C API it wraps to
be more Ada-ish.

However, if you want to write a thick binding, it is probably a good idea to develop
the thin binding it needs along with it. Using an existing thin binding has some
drawbacks:

 * A standalone thin binding is designed to have a universal API that can be used
   directly in any code. When you write a thick wrapper, you will probably notice
   that it's more convenient to have a specialized thin wrapper so you have complete
   control of the types it uses. As you can wrap C types in quite a number of ways
   (especially when it comes to pointers), a universal wrapper may use types in its
   Ada declarations which are inconvenient for implementing a thick wrapper.
 * The thin binding will be publicly visible. A user of your thick binding may choose
   to use the thin binding for some tasks. I consider this to be a bad thing, because
   it can hide shortcomings of your thick binding (users don't complain, but just use
   the thin binding instead). If you use some sophisticated code in your thick
   binding, it might even break when users also have access to the thin binding.
 * You are dependent on the thin binding (in the case that the thin binding is
   provided by a third party). A binding for a C library really should not have a
   dependency to anything but the C library.

Whether you write a thin or a thick binding is your decision. Keep in mind that a
thin binding is less work for you, but more work for whoever wants to use the thin
binding. After all, _someone_ has to marshal the raw C types to more convenient Ada
types.

Here are some reasons why you may _not_ want to write a thick binding:

 * Your API differs from the one of the C API. This may scare users who are familiar
   with the C API away. It also requires you to write some documentation on your API.
   When you write a thin binding, the libraries' documentation suffices for using your
   binding.
 * You can autogenerate a thin binding from the libraries' C header with [Swig][3].
   The GNAT compiler is also able to automatically create Ada bindings with
   [`-fdump-ada-spec`][4]. Writing a thick binding is much more work.

This concludes my thoughts on thin vs. thick bindings.  In the next post, I will
actually show how to write some code.

## Types and Conventions

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

### Structs

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

### Arrays

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

### Enumerations

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

### Strings

In C, there are no strings. Well, not really. Whenever you want to have a string,
you actually use a `char` array that is terminated by a null character. This
special kind of array is available in Ada at `Interfaces.C.Strings`. It provides
conversions from and to an Ada `String`. Just use that package.

## Declaring the Subprograms in Ada

Now that we have defined the needed types in Ada, we need to translate the C
declarations to Ada.

### By-value vs. By-reference

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

### Import Statements

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

## Void Pointers

C has no generics. So whenever a subprogram parameter may take differently typed values,
a void pointer is used. Usually, a void pointer value will be used in one of these ways:

 * It will be passed on to another subprogram that will know its type, cast it
   appropriately and do stuff with it.
 * It will be used to return data to the caller, and he has to know what to do with it.

Here's an example for the second case:

{% highlight c %}
void * clGetExtensionFunctionAddress(const char * func_name);
{% endhighlight %}

Here, a void pointer is returned to the caller. The purpose of this function is to return
a pointer to a subprogram specified with *func_name*. So there is a fixed set of accepted
values for *func_name*, and for every value, the function may return a differently typed
pointer to a subprogram.

There are several possibilities to wrap C functions taking void pointers in Ada:

### Import it multiple times with different signatures

{% highlight ada %}
package C renames Interfaces.C;
type Func_Type1 is access function return C.int;
pragma Convention (C, Func_Type1);
type Func_Type2 is access function (Param : C.int) return C.double;
pragma Convention (C, Func_Type2);
function Get_Extension_Function_Address
  (Func_Name : C.Strings.chars_ptr) return Func_Type1;
function Get_Extension_Function_Address
  (Func_Name : C.Strings.chars_ptr) return Func_Type2;
pragma Import (Convention => C, Entity => Get_Extension_Function_Address,
               External_Name => "clGetExtensionFunctionAddress");
{% endhighlight %}

The Import pragma will be applied to all functions that match the given name. While this
works, it does not give us type safety: If the user calls the wrong function, he gets a
function reference back that will not work as expected.

### Wrap the C function

{% highlight ada %}
function Backend (Func_Name : C.char_array) return System.Address;
pragma Import (Convention => C, Entity => Backend,
               External_Name => "clGetExtensionFunctionAddress");

generic
   type Return_Type is private;
   Function_Name : String;
function Get_Extension_Function_Address return Return_Type is
   function Convert is new Ada.Unchecked_Conversion
     (System.Address, Return_Type);
begin
   return Convert (Backend (C.To_C (Function_Name)));
end Get_Extension_Function_Address;
function Get_Func1 is new Get_Extension_Function_Address
  (Func_Type1, "func1");
function Get_Func2 is new Get_Extension_Function_Address
  (Func_Type2, "func2");
{% endhighlight %}

Obviously, you want to expose just the last two functions to the caller. As you cannot
implement a declaration made in a package specification by a generic instantiation,
you have to use `renames` to do that:

{% highlight ada %}
function Get_Func1_Public return Func_Type1 renames Get_Func1;
{% endhighlight %}

### Provide a generic interface
... so the caller can define the type he wants to use. This is useful in cases like this:

{% highlight c %}
void registerCallback(void(*callback)(void* user_data), void* user_data);
{% endhighlight %}

Here, the C procedure lets the caller register a callback that, when called, will be
passed a pointer to some data the caller provides. This is a pattern that is often
used with callbacks in C. You can wrap it like this:

{% highlight ada %}
procedure Backend (Callback_Raw, User_Data : System.Address);
pragma Import (Convention => C, Entity => Backend,
               External_Name => "registerCallback");
generic
   type User_Data_Type is private;
   type User_Data_Access is access User_Data_Type;
   type Callback is access procedure (User_Data : User_Data_Type);
procedure Register_Callback (Target    : Callback;
                             User_Data : User_Data_Access) is
   function Convert_User_Data is new Ada.Unchecked_Conversion
     (User_Data_Access, System.Address);
   function Convert_Callback is new Ada.Unchecked_Conversion
     (Callback, System.Address);
begin
   Backend (Convert_Callback (Target), Convert_User_Data (User_Data));
end Register_Callback;
{% endhighlight %}

You may want to convert this code to a generic package that can define the
types `User_Data_Access` and `Callback` itself based on the parameter
`User_Data_Type`, particularly if there are multiple similar callback
registering functions.

Be aware that this wrapper leaves it to the caller to make sure his callback
function has the correct convention (one can also use the pragma Convention
on subprograms that are implemented in Ada if they will be called by C code).

If you want to make your wrapper even thicker, you can define your own `User_Data_Type`
and callback function, and embed the reference to the caller's function
as well as the caller's data in your `User_Data_Type`. Your callback function can
then extract the subprogram reference and user data from your container and call the
callback the caller provided. This way, the caller does not need to apply any pragmas
in his code.

### Conclusion

If you want to wrap a void pointer, you usually declare it as `System.Address`
and use `Ada.Unchecked_Conversion` in your wrapper. The lesser the caller needs to take
care about Convention pragmas, the easier your wrapper is to use.

## Bitfields

Bitfields are usually declared as numeric type like `int` in C. Then, a number of constants
is defined that can be combined with bitwise OR to build a value of the bitfield. Example:

{% highlight c %}
typedef cl_ulong            cl_bitfield;
typedef cl_bitfield         cl_device_type;

/* cl_device_type - bitfield */
#define CL_DEVICE_TYPE_DEFAULT                      (1 << 0)
#define CL_DEVICE_TYPE_CPU                          (1 << 1)
#define CL_DEVICE_TYPE_GPU                          (1 << 2)
#define CL_DEVICE_TYPE_ACCELERATOR                  (1 << 3)

cl_int clGetDeviceIDs(cl_platform_id   /* platform */,
                      cl_device_type   /* device_type */,
                      cl_uint          /* num_entries */,
                      cl_device_id *   /* devices */,
                      cl_uint *        /* num_devices */);
{% endhighlight %}

Of course, you could just copy the constants to Ada and provide the same interface.
But you can also wrap it with a record:

{% highlight ada %}
type Device_Type is record
   Default     : Boolean := False;
   CPU         : Boolean := False;
   GPU         : Boolean := False;
   Accelerator : Boolean := False;
end record;
for Device_Type use record
  Default     at 0 range 0 .. 0;
  CPU         at 0 range 1 .. 1;
  GPU         at 0 range 2 .. 2;
  Accelerator at 0 range 3 .. 3;
end record;
for Device_Type'Size use ULong'Size;
pragma Convention (C_Pass_By_Copy, Device_Type);
{% endhighlight %}

This way, the possible values are directly linked to the type. If you
just provide constants and a numeric type, there is no explicit link between
them.

## Final words

In this article, I have shown some techniques for wrapping general C APIs in Ada.
I have also written two articles detailing the implementation of OpenGLAda in AdaCore's blog, which go a bit more in-depth about challenges of a thick wrapper:

 * [Part 1][5]
 * [Part 2][6]

[1]: http://flyx.github.io/OpenCLAda/
[2]: http://flyx.github.io/OpenGLAda/
[3]: http://gnuada.svn.sourceforge.net/viewvc/gnuada/trunk/projects/swig-1.3.35/
[4]: http://www.adacore.com/adaanswers/gems/gem-59/
[5]: https://blog.adacore.com/the-road-to-a-thick-opengl-binding-for-ada
[6]: https://blog.adacore.com/the-road-to-a-thick-opengl-binding-for-ada-part-2