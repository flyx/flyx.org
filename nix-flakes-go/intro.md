---
layout: default
title: "Exploring Nix Flakes: Usable Go Plugins"
title_short: Nix Flakes and Go
kind: article
permalink: /nix-flakes-go/
weight: 5
date: 2021-12-30
---

[Go](https://go.dev/) supports plugins, sort of:
It has a `-buildmode=plugin` that lets you create `.so` files, which can then be loaded as plugin in a Go application.

However, it [doesn't work on Windows][1], it [doesn't work well with vendoring][2], and since [shared libraries are deprecated][3], every plugin is huge because they can't share even the standard library with the main application.
To sum up, `-buildmode=plugin` is in a sorry state.
 
In this article, I will show an alternative approach to building an application in Go that supports plugins.
I will use [Nix Flakes][4] as build system and specifically for plugin management, and I will assume you are familiar with it.
Familiarity with Go is also assumed.

This article may also be interesting for people who simply are curious how to use Nix with Go.
To follow the instructions in this article, you need `Nix` installed and Flake support enabled.
Let's get started.
 
 [1]: https://github.com/golang/go/issues/19282
 [2]: https://github.com/golang/go/issues/20481
 [3]: https://github.com/golang/go/issues/47788
 [4]: https://nixos.wiki/wiki/Flakes

## Concepts

The general approach is as follows:

 * The main application is a Nix Flake.
 * Plugins are Nix Flakes.
 * The final application is a Nix derivation that is generated from a list of plugins and outputs an executable that uses the given plugins.

Now, you are perhaps thinking

> If we need to compile the whole application with a known list of plugins, those are not really plugins, but build flags.

and that is not entirely wrong.
However the Nix philosophy is to declaratively define your system state, so for any application with plugin support, you'd have a Nix derivation generated from the list of plugins anyway.
Compared to classical flags in a build system, using Nix Flakes does allow us to

 * fetch plugins from elsewhere.
 * add plugins the original application is not aware of.
 * check whether our application version and plugin version are compatible.

What we actually lose is the possibility to combine readily compiled binaries, i.e. someone who wants to setup the application with their hand-chosen set of plugins must use Nix to compile their executable.
Scenarios where this is impossible seem to be exotic, at least with Go projects (yes I will show later that we can build Windows binaries even though Nix doesn't support Windows).
