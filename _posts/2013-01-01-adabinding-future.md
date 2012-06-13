
## 2 Basics

### 2.1 Getting started

The first thing you should do when starting to write your wrapper is to get to know how the
library works. You are not just translating code (as you would for a thin wrapper), so you
have to know the architecture and purpose of all the parts of the library.

I suggest to have a thin wrapper within your thick wrapper that holds all the imported
functions from the C library. This does not need to be exposed, so I usually put it into
a private package that is only visible to the wrapper, like this one:

{% highlight ada %}
private package CL.API is

   -- here be imported functions

end CL.API;
{% endhighlight %}

### 2.2 Primitive and enumeration types

The primitive types provided by the C language are available in the Ada standard library under
`Interfaces.C`. If there are `typedef`s in the C header that use those types, create appropriate
types or subtypes in the Ada wrapper.

A special case are boolean values: As C does not provide a boolean type, most C headers define
constants for `FALSE` and `TRUE` mapping to 0 and 1 respectively. Then, a numeric type is used
in cases where a boolean has to be provided or is returned. You can wrap this pseudo-boolean as
follows:

{% highlight ada %}
type Bool is new Boolean;
for Bool use (False => 0, True => 1);
for Bool'Size use Interfaces.C.int'Size;
{% endhighlight %}

In this case, the C type `int` is used for passing boolean values. You should not expose this
type in your wrapper. Instead, just case any values from the standard Ada `Boolean` to this
`Bool` type and back when calling the C functions.

What works for booleans also works for all other enumeration types. In most C libraries,
enumerations are defined by using a numeric type like `int` for transportation and constant
values defined via `#define` for the possible values. It may look like this:

{% highlight c %}
/* Comment that states what this "enumeration" is used for */
#define VALUE1   0x0001
#define VALUE2   0x0002
#define VALUE3   0x0003
#define VALUE4   0x0010
#define VALUE5   0x0020
{% endhighlight %}

This can be translated into Ada like this:

{% highlight ada %}
type Some_Type is (Value1, Value2, Value3, Value4, Value5);
for Some_Type use (Value1 => 16#0001#,
                   Value2 => 16#0002#,
                   Value3 => 16#0003#,
                   Value4 => 16#0010#,
                   Value5 => 16#0020#);
for Some_Type'Size use Interfaces.C.int'Size;
{% endhighlight %}

As before, the transporting type may vary.

### 2.3 Structs

Structs in C are like records in Ada, so this should be easy. Right? Wrong.

The main problem here is that in Ada, record types are passed by reference. In C, structs are passed
by value. So, when you define a record that should be passed to a C function, you have to tell the
Ada compiler that you want it passed by value:

{% highlight ada %}
type Point is record
   X : Interfaces.C.int;
   Y : Interfaces.C.int;
end record;
pragma Convention (C_Pass_By_Copy, Point);
{% endhighlight %}

Of course, this isn't needed in the case that a C function expects a *pointer* to a struct as
parameter. Instead of defining the parameter passing convention for the record, you can also
define it when importing the C function (see below). If you don't want to define the Ada record
to be passed by value, you can use `pragma Convention (C, Point);` instead. This ensures that
the layout of the record corresponds with what the C function expects.

### 2.4 Pointers

To be continued...