---
layout: post
title: Writing Ada Bindings for C Libraries, Part 3
tags: [ada, programming]
---

[Previously...][1]

### Void Pointers

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

There are several possibilities to wrap this function in Ada:

 * Import it multiple times with different signatures:
   
   {% highlight ada %}
   package C renames Interfaces.C;
   type Func_Type1 is access function return C.int;
   pragma Convention (C, Func_Type1);
   type Func_Type2 is access function (Param : C.int) return C.double;
   pragma Convention (C, Func_Type2);
   function Get_Extension_Function_Address (Func_Name : C.Strings.chars_ptr) return Func_Type1;
   function Get_Extension_Function_Address (Func_Name : C.Strings.chars_ptr) return Func_Type2;
   pragma Import (Convention => C, Entity => Get_Extension_Function_Address,
                  External_Name => "clGetExtensionFunctionAddress");
   {% endhighlight %}
   
   The Import pragma will be applied to all functions that match the given name. While this
   works, it does not give us type safety: If the user calls the wrong function, he gets a
   function reference back that will not work as expected.

 * Wrap the C function:
   
   {% highlight ada %}
   function Backend (Func_Name : C.char_array) return System.Address;
   pragma Import (Convention => C, Entity => Backend,
                  External_Name => "clGetExtensionFunctionAddress");
   
   generic
      type Return_Type is private;
      Function_Name : String;
   function Get_Extension_Function_Address return Return_Type is
      function Convert is new Ada.Unchecked_Conversion (System.Address, Return_Type);
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

 * Provide a generic interface so the caller can define the type he wants to use. This
   is useful in cases like this:
   
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
   procedure Register_Callback (Target : Callback; User_Data : User_Data_Access) is
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

Conclusion: If you want to wrap a void pointer, you usually declare it as `System.Address`
and use `Ada.Unchecked_Conversion` in your wrapper. The lesser the caller needs to take
care about Convention pragmas, the easier your wrapper is to use.

### Bitfields

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

[1]: /2012/06/14/adabindings2/