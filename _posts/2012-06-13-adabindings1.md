---
layout: post
title: Writing Ada Bindings for C Libraries, Part 1
tags: [ada, programming]
---

This article gives an overview over problems, solutions and guidelines for writing an
Ada binding for a C library. It summarizes experiences I made while implementing
[OpenCLAda][1] and [OpenGLAda][2]. Code examples are taken from those projects.

The Ada code examples shown here are written in Ada 2005. Note that you can import C
functions somewhat nicer in Ada 2012.

### Thin or Thick?

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
               cl_uint *        /* num_devices */) CL_API_SUFFIX__VERSION_1_0;
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

[To be continued...][5]

[1]: http://flyx86.github.com/OpenCLAda/
[2]: http://flyx86.github.com/OpenGLAda/
[3]: http://gnuada.svn.sourceforge.net/viewvc/gnuada/trunk/projects/swig-1.3.35/
[4]: http://www.adacore.com/adaanswers/gems/gem-59/
[5]: /2012/06/14/adabindings2/