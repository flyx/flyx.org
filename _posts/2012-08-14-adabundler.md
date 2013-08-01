---
layout: post
title: Writing applications in Ada with ada-bundler
tags: [ada, programming]
---

Cross-platform development of desktop applications is a tedious business. You can
compile simple Ada code without modifications on any platform that's supported by
your compiler, but as soon as you start developing desktop applications (usually
with a GUI), you need to implement quite some platform-specific behaviour. In this
post, I present **ada-bundler**, a low-level library and tool for cross-platform file
access that aims to make your life easier a bit.

### The Problem

If you look at the platforms and languages used commonly for application development
today, you'll see that there are lots of build systems that take care of bundling
resource files with your application - be it pictures, configuration files or other
data your application needs. IDEs just let you add resource files to your project
and will bundle them with the compiled binary when you build the application.
GPRBuild, the build system commonly used for Ada applications, does not support
handling resource files at all - it focuses on compilation of sources.

Bundling files with your application is platform-specific: Native Windows apps may
embed them as resources right in the executable file. OSX applications come as
so-called "app bundle", which is basically a folder containing all the application
files, which the user can double-click to start the application. Linux puts
resources in folders like `/usr/share`. So if you want to properly support these
three major operating systems, you have to look at all these places for your files.

### Introducing ada-bundler

ada-bundler aims to provide an abstract layer with a univeral API for accessing
resource files on these operating systems. It has been written to help developers
bundling desktop applications written in Ada. To show you how to use it, let's have
a look at some example code.

#### Writing the ada-bundler configuration file

Consider you have an application named *Example*. This application needs two
data files and a configuration file which should be bundled with it. We start with
writing the ada-bundler configuration for this application. The ada-bundler
configuration file is a [YAML][1] file. Let's see how it looks:

{% highlight yaml %}
name: Example
version: "0.1"
executable: bin/example
data:
  - data/file1.txt
  - data/file2.txt
configuration:
  - configuration/conf.txt
{% endhighlight %}

The contents is quite straight forward: Firstly, you define the name and the version
number of your application. Then, you tell ada-bundler where to find the primary
executable file. After that comes the payload: You tell ada-bundler which resource
files should be bundled with your application. The items are paths relative to the
current directory (i.e. the directory where you run ada-bundler from; that should
usually be the directory where the ada-bundler configuration file is located).

Instead of file names, you can also specify whole directories. If you do, all the
contents of the directory is bundled with your application. 

To be able to create a nice application bundle for each target platform, ada-bundler
needs some platform-specific configuration - this is the second part of our
configuration file:

{% highlight yaml %}
osx:
  icon: icon.icns
  identifier: com.example.example
windows:
  icon: icon.ico
linux:
  data:
    - data/linux-specific-file.txt
{% endhighlight %}

To create an OSX app bundle, you need to provide at least an identifier and an icon
file. The identifier is usually something like *com.yourcompany.applicationname*. You
can create the icon file with  the `iconutil` [command line tool][2].

For Windows, you only need to provide an icon file. that file will be embedded in your
executable file. It must be an `*.ico` file.

For Linux, there are no obligatory files that need to be provided. In the example, you
see that I add another data file in the `linux` section. This file will only be bundled
when you bundle your application with Linux as target system. You can add additional
configuration and data files to every operating system section.

#### Using ada-bundler in your code

The ada-bundler API is provided with the Ada package `Bundle`. In the initialization
code of your application, you have to tell ada.bundler the name of the folder in
which user-specific files of your application should be stored. Usually, this equals
the name of your application. After that, you can ask it for the path to one of the
resource files you specified in the configuration file:

{% highlight ada %}
with Ada.Text_IO;

with Bundle;

procedure Example is
   use Ada.Text_IO;
begin
   -- initialization: 
   Bundle.Set_Application_Folder_Name ("Example");
   -- getting the paths to your files
   declare
      Data_Path_1        : String := Bundle.Data_Path ("file1.txt");
      Data_Path_2        : String := Bundle.Data_Path ("file2.txt");
      Configuration_Path : String := Bundle.Data_Path ("conf.txt");
      
      Data_File_1 : File_Type;
   begin
      Open (Data_File_1, In_File, Data_Path_1);
      -- do something useful here
      Close (Data_File_1);
   end;
end Example;
{% endhighlight %}

Note that when you reference the files you bundled with your application, they
are located directly in the base directory where your resource files lie - even
if you included them from subfolders like `data/file1.txt`. Of course, if you
copy whole directories, the file structure in the directory is preserved.

You can also get paths to user-specific files you want to create or read:

{% highlight ada %}
declare
   User_File_Path : String := Bundle.User_Data_Path ("subfolder/user-data.txt");
begin
   -- do something useful here
end;
{% endhighlight %}

Note that you can give relative paths here, and by default, the containing folders
will be created when you query for the file path. You can change this behaviour by
setting the optional second parameter of `User_Data_Path` to `False`.

To include ada-bundler in your application, the simplest way is to add its gpr file
as dependency in your project's gpr file:

{% highlight ada %}
with "ada_bundler.gpr";
project Example is
   for Main use ("example");
   -- ...
end Example;
{% endhighlight %}

`ada_bundler.gpr` has to be found in your `ADA_PROJECT_PATH` environment variable.
You can also just add it to your project's folder.

When you call GPRBuild, you have to specify the target platform by setting the
`packaging` variable:

    $ gprbuild example.gpr -Xpackaging=MacOSX

Possible values are `MacOSX`, `Windows` and `Linux_Universal`. The latter one is
named like this because I may possibly add support for RPM and / or DEB packages
in the future.

#### Using the ada-bundler tool

You're ready to bundle your application now! The bundling is implemented with a
single script file written in Python, named `ada-bundler.py`. It takes up to two
arguments: The first is the name of your ada-bundler configuration file. It defaults
to `bundle.yaml`. The second is the name of your target system; either `osx`,
`windows` or `linux`. It defaults to your host system.

You can integrate ada-bundler in your build process with a Makefile. Here is a
simple example:

{% highlight makefile %}
GPRBUILD = gprbuild -p

PACKAGING := Windows
UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
   PACKAGING := MacOSX
endif
ifeq ($(UNAME), Linux)
   PACKAGING := Linux_Universal
endif


all: bundle

compile:
   mkdir -p bin
   mkdir -p obj
   ${GPRBUILD} -P example.gpr -Xpackaging=${PACKAGING}

bundle: compile
   python ../src/tool/ada-bundler.py

clean:
   rm -rf ./obj ./bin
{% endhighlight %}

### What ada-bundler cannot do

ada-bundler is not a GUI library. To write a cross-platform desktop application
with a graphical user interface, you need a library like [GTK][3] or [Qt][4]. There
are Ada bindings for both libaries. A promising Ada project aiming to provide
a user interface library is [Lumen][5]. If you want to create an OpenGL-based
application, you can use [AdaOpenGL][6].

If your application has dependencies on dynamic libraries, you may need to bundle
them with your application. This is currently not possible, it will need some
planning and diving into the linux packaging systems, because an RPM / DEB backend
probably wants to add dependencies to the packages your application depends on
instead of bundling the libraries.

### Getting ada-bundler

ada-bundler is available at [GitHub][7].

 [1]: http://yaml.org/
 [2]: https://developer.apple.com/library/mac/#documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html#//apple_ref/doc/uid/TP40012302-CH7-SW2
 [3]: http://gtk.org/
 [4]: http://qt.nokia.com/
 [5]: http://www.niestu.com/software/lumen/
 [6]: http://flyx.github.io/OpenGLAda/
 [7]: https://github.com/flyx/ada-bundler
