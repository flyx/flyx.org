---
layout: default
title: "Exploring Nix Flakes: Build LaTeX Documents Reproducibly"
title_short: Nix Flakes and LaTeX
kind: article
permalink: /nix-flakes-latex/
weight: 4
date: 2021-11-17
updated: 2021-12-28
---

This article shows how to use [Nix Flakes](https://nixos.wiki/wiki/Flakes) to build LaTeX documents.
It is not particularly beginner-friendly to keep it at manageable size.

If you don't know much about Nix and are in a hurry, I recommend [*this article*](https://serokell.io/blog/practical-nix-flakes) for a quick overview of the language and Flakes.
A proper way to learn about Nix is the [*Nix Pills*](https://nixos.org/guides/nix-pills/) series, and [*this series*](https://www.tweag.io/blog/2020-05-25-flakes/) about Nix Flakes.

The proper way to learn LaTeX is to take any vaguely math-related academic course and be peer-pressured into trying it out until it works.
Jokes aside, this probably isn't an interesting read for people who are not already familiar with LaTeX; while I will explain the things I'm doing with Nix, the LaTeX code I will just throw at you assuming you can read it.

**Metered connection users:** Be aware that the instructions in this article download quite a bit of data from the internet.

## Getting Started

In an empty directory, let's start a `document.tex` file like this:

{% highlight latex %}
\documentclass[a4paper]{article}

\begin{document}
  Hello, World!
\end{document}
{% endhighlight %}

Now we want to tell Nix how to build this document.
To do this, create a file `flake.nix` with the following content:

{% highlight nix %}
{
  description = "LaTeX Document Demo";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.05;
    flake-utils.url = github:numtide/flake-utils;
  };
  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib; eachSystem allSystems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      tex = pkgs.texlive.combine {
          inherit (pkgs.texlive) scheme-minimal latex-bin latexmk;
      };
    in rec {
      packages = {
        document = pkgs.stdenvNoCC.mkDerivation rec {
          name = "latex-demo-document";
          src = self;
          buildInputs = [ pkgs.coreutils tex ];
          phases = ["unpackPhase" "buildPhase" "installPhase"];
          buildPhase = ''
            export PATH="${pkgs.lib.makeBinPath buildInputs}";
            mkdir -p .cache/texmf-var
            env TEXMFHOME=.cache TEXMFVAR=.cache/texmf-var \
              latexmk -interaction=nonstopmode -pdf -lualatex \
              document.tex
          '';
          installPhase = ''
            mkdir -p $out
            cp document.pdf $out/
          '';
        };
      };
      defaultPackage = packages.document;
    });
}
{% endhighlight %}

Our inputs are `nixpkgs`, the main Nix package repository, from which we primarily need *TeX Live*, and `flake-utils`, a library that provides some convenience functions.

For defining our outputs, we use `eachSystem` (from `flake-utils`) to define an output package for each system in `allSystems` – we do want users on any system to be able to compile our document.

The important bit `pkgs.texlive.combine` builds a TeX Live installation containing the TeX Live packages we specify.
For building our minimal document, we start with `scheme-minimal` and include `latex-bin` (to have `lualatex`) and `latexmk` (our helper script to build the document).

Then, we define our output package *document*.
Since building LaTeX document requires no C compiler, we use `stdenvNoCC`.
We need the phases *unpack* (to access our source code), *build* (to typeset the document) and *install* (to copy the PDF into `$out`).

`latexmk` is a script that continuously calls our LaTeX processor (in this case, `lualatex`) until the document reaches a fixpoint.
`lualatex` needs writable cache directories, which we create and communicate via environment variables.
`-interaction=nonstopmode` will cause `lualatex` to not stop and ask for user input in case an error is encountered, as it would by default.
By the way, we use `lualatex` instead of `pdflatex` simply because it is the more modern alternative, supporting UTF-8, TTF/OTF Fonts, etc.

In the *install* phase, we create the `$out` directory and copy the created document into it.
We could instead make our document itself be `$out` (because it is the only output file of our derivation), but having a PDF file without `.pdf` extension felt weird, so I created a containing directory.

Now let's pin our input flakes to their current versions by doing

{% highlight bash %}
nix flake lock
{% endhighlight %}

For those not familiar with Flakes, this will create a file `flake.lock` (feel free to explore its contents).
From now on, we are working on specific versions of our inputs, which are described in `flake.lock`.

One last thing before we can build our document:
The variable `self` will only contain those files of our source that are checked into version control.
So we'll do

{% highlight bash %}
git init
git add flake.{nix,lock} document.tex
git commit -m "initial commit"
{% endhighlight %}

When that's done, we can build our document with

{% highlight bash %}
nix build
{% endhighlight %}

This will take some time, but will eventually create a directory `result` which contains `document.pdf`.
Actually, `result` is a symlink which can be inspected via

{% highlight bash %}
readlink result
{% endhighlight %}

And it points to our `/nix/store`.

As shown by this minimal example, our `flake.nix` is not just a build system, but also manages all dependencies that are required to build our document.

## Producing Identical Documents <span class="note">added 2021-11-30</span>

To be truly reproducible, the PDF file we create must always be exactly the same.
This is currently not the case for two reasons:

 * LaTeX likes to put the generation date into the document.
   This obviously happens when you query it e.g. with `\today`, but the date also gets filled into the PDF's *Creation date* attribute.
 * The resulting PDF has a seemingly random ID value added into the PDF's xref table.

The fix to the first problem depends a bit on whether you're using `\today`, and if so, what for.
For example, when rendering a letter, you *do want* the date on the letter to be the one from when you generated it (or more precisely, when you sent it, but we cannot do anything about it after the PDF has been created).

The tool we need to solve the problem is the environment variable `SOURCE_DATE_EPOCH`.
If we set it to a Unix timestamp, LaTeX will use that instead of the current date.
We thus modify the call to `latexmk` like this:

{% highlight plain %}
env TEXMFHOME=.cache TEXMFVAR=.cache/texmf-var \
   SOURCE_DATE_EPOCH=${toString self.lastModified} \
   latexmk -interaction=nonstopmode -pdf -lualatex \
   document.tex
{% endhighlight %}

`self.lastModified` is set to the Unix timestamp of the last commit in our repository.
This seems to be a reasonable date to set, but in the case of a letter, I would actually advise to explicitly set the date, e.g.

{% highlight plain %}
env TEXMFHOME=.cache TEXMFVAR=.cache/texmf-var \
  SOURCE_DATE_EPOCH=$(date -d "2021-11-30" +%s) \
  latexmk -interaction=nonstopmode -pdf -lualatex \
  document.tex
{% endhighlight %}

This way, you will always know when you sent the letter.
I used the `date` utility so that the date is readable.
You can of course put it into a nix variable in the Flake and interpolate it into the command if you want.

Now that we have fixed the date, we still have the ID.
That ID is actually calculated from the system date and time, and the full path of the generated PDF file, and thus we won't be able to modify it to our needs from the outside.
There are however TeX commands we can use:

{% highlight latex %}
% LuaTeX
\pdfvariable suppressoptionalinfo 512\relax
% pdfTeX
\pdftrailerid{}
% XeTeX
\special{pdf:trailerid [
    <00112233445566778899aabbccddeeff>
    <00112233445566778899aabbccddeeff>
]}
{% endhighlight %}

XeTeX is the only backend that seems not to be able to omit the ID, so the command is setting it to some literal value.
Since we're using LuaLaTeX, we want the LuaTeX solution.
And since this is irrelevant to the document's content, let's prepend it to the input via latexmk:

{% highlight plain %}
env TEXMFHOME=.cache TEXMFVAR=.cache/texmf-var \
  SOURCE_DATE_EPOCH=$(date -d "2021-11-30" +%s) \
  latexmk -interaction=nonstopmode -pdf -lualatex \
  -pretex="\pdfvariable suppressoptionalinfo 512\relax" \
  -usepretex document.tex
{% endhighlight %}

With this, we have a truly reproducible PDF output.
Now, let's explore what happens when we use packages in our LaTeX document.

## TeX Live Packages

Let's say we want to have a nice tabular in our `document.tex`:

{% highlight latex %}
\documentclass[a4paper]{article}

\usepackage{nicematrix}

\begin{document}
  \begin{NiceTabular}{p{5.5cm}|p{2cm}}
  \CodeBefore
    \rowcolors{2}{white}{gray!30}
  \Body \hline
    droggel & 23 \\ \hline
    jug     & 42 \\ \hline
  \end{NiceTabular}
\end{document}
{% endhighlight %}

However, our current *TeX Live* configuration does not provide `nicematrix`.
The packages we provide in `pkgs.texlive.combine` are defined by [tlmgr](https://www.tug.org/texlive/tlmgr.html), TeX Live's package manager.
Usually, the name we give in `\usepackage` is the name of the package we need to include, so let's test that:

{% highlight nix %}
    # […]
    let
      pkgs = nixpkgs.legacyPackages.${system};
      tex = pkgs.texlive.combine {
        inherit (pkgs.texlive) scheme-minimal latex-bin latexmk
        nicematrix;
      };
    in rec {
    # […]
{% endhighlight %}

Don't forget to commit all changes to git before building (we'll just amend our initial commit):

{% highlight bash %}
git commit -a --amend --no-edit
nix build
{% endhighlight %}

While `nicematrix` is indeed the correct package here, we'll run into an error.
It turns out, `nicematrix` requires some additional packages to work and we didn't include them.
Can you figure out which ones? I'll wait.

<br style="line-height: 5em;"/>

If you actually tried to tackle this problem, you have probably read the log, which tells you some `.sty` files are missing, and then tried to include their names in `pkgs.texlive.combine`.
That only brings you so far, because *some* `.sty` files are included in packages that carry a different name. 
The following is the complete list of packages we need:

{% highlight nix %}
    # […]
    let
      pkgs = nixpkgs.legacyPackages.${system};
      tex = pkgs.texlive.combine {
        inherit (pkgs.texlive) scheme-minimal latex-bin latexmk
        tools amsmath pgf epstopdf-pkg nicematrix infwarerr grfext
        kvdefinekeys kvsetkeys kvoptions ltxcmds;
      };
    in rec {
    # […]
{% endhighlight %}

For reference, all existing packages are listed in [this file](https://github.com/NixOS/nixpkgs/blob/nixos-21.05/pkgs/tools/typesetting/tex/texlive/pkgs.nix), however this list is hardly helpful without meta information about the packages.
In a usual TeX Live installation, you could use `tlmgr search --file <missing>` to find out which package contains a file, but nixpkgs does not provide this utility.
For all I know, that information is not easily queryable on the internet either.

Of course, we only need to run around and collect all these packages because we started with the *minimal* scheme.
Switching to the *basic* scheme will provide almost all packages we need:

{% highlight nix %}
    # […]
    let
      pkgs = nixpkgs.legacyPackages.${system};
      tex = pkgs.texlive.combine {
        inherit (pkgs.texlive) scheme-basic latexmk pgf nicematrix;
      };
    in rec {
    # […]
{% endhighlight %}

This shows that we basically choose how much work we want to put into listing our TeX dependencies.
If we start with a larger scheme, it is less work but we will download more packages than necessary.
The laziest way would of course be to just include `scheme-full`.
Nix' philosophy is instead to only list the dependencies we *actually* need.
I would say that starting with `scheme-basic` is generally fine.

Don't forget to check out the new document we can now create with `nix build`!

## System Fonts <span class="note">rewritten 2021-12-28</span>

While TeX Live does provide us with a lot of fonts to choose from, we might eventually want to use a font no available there.
Assume we want to use the [Fire Code](https://github.com/tonsky/FiraCode).
This font is packaged in `nixpkgs.fira-code`.
Let's have a quick look at what is contained in that package:

{% highlight bash %}
nix shell nixpkgs#fira-code -c bash
STORE_PATH=$(nix eval --raw --impure --expr "(import <nixpkgs> {}).fira-code.outPath")
(cd $STORE_PATH && du -a .)
exit # the shell we just started
{% endhighlight %}

(I'm using bash here because syntax is different for some shells like *fish*, and `nix shell`, unlike the old `nix-shell`, by default launches your default shell.)
This gives us:

    560	./share/fonts/truetype/FiraCode-VF.ttf
    560	./share/fonts/truetype
    560	./share/fonts
    560	./share
    560	.

Now we need to set the `OSFONTDIR` environment variable so that LuaTeX can find it (mind that having the font package as build input does not make the font visible to LuaTeX).
We also need to add `fontspec` to our `tex` package.
Let's update `flake.nix`:

{% highlight nix %}
    # […]
    let
      pkgs = nixpkgs.legacyPackages.${system};
      tex = pkgs.texlive.combine {
        inherit (pkgs.texlive) scheme-minimal latex-bin latexmk
        nicematrix fontspec;
      };
    in rec {
      packages = = {
        document = pkgs.stdenvNoCC.mkDerivation rec {
          name = "latex-demo-document";
          src = self;
          buildInputs = [ pkgs.coreutils pkgs.fira-code tex ];
          phases = ["unpackPhase" "buildPhase" "installPhase"];
          buildPhase = ''
            export PATH="${pkgs.lib.makeBinPath buildInputs}";
            mkdir -p .cache/texmf-var
            env TEXMFHOME=.cache TEXMFVAR=.cache/texmf-var \
                OSFONTDIR=${pkgs.fira-code}/share/fonts \
              latexmk -interaction=nonstopmode -pdf -lualatex \
              document.tex
          '';
          installPhase = ''
            mkdir -p $out
            cp document.pdf $out/
          '';
        };
      };
      # […]
{% endhighlight %}

We can now reference to the font in our document.
However, we might not be completely sure about the name we need to use to refer to the font – is it `FiraCode`, `Fira-Code` or `Fira Code`?
Font files tend to be a bit inconsistent about this.
So let us check it:

{% highlight bash %}
nix shell nixpkgs#fira-code nixpkgs#fontconfig -c bash
STORE_PATH=$(nix eval --raw --impure --expr "(import <nixpkgs> {}).fira-code.outPath")
fc-scan $STORE_PATH/share/fonts/truetype/FiraCoed-VF.ttf | grep family
exit
{% endhighlight %}

This will give us some lines like

    family: "Fira Code"(s) "Fira Code Light"(s)

the latter, `Fira Code Light`, is the correct one (I am not quite sure why, but the former won't work).
Thus, we update our `document.tex`:

{% highlight latex %}
\documentclass[a4paper]{article}

\usepackage{fontspec}
\setmonofont{Fira Code Light}

\usepackage{nicematrix}

\begin{document}
  \begin{NiceTabular}{p{5.5cm}|>{\ttfamily}p{2cm}}
  \CodeBefore
    \rowcolors{2}{white}{gray!30}
  \Body \hline
    droggel & 23 \\ \hline
    jug     & 42 \\ \hline
  \end{NiceTabular}
\end{document}
{% endhighlight %}

Save and run `nix build`.
The second column in the document will now use the *Fira Code* font.
Success!

### Local Font Files

You may want to use fonts that are neither available as TeX Live package, nor in nixpkgs.
Maybe you want to use a fancy commercial font.
While it is no problem to append the working directory or a `fonts` subdirectory to `OSFONTDIR`, you can also define a separate derivation for that font:

{% highlight nix %}
    # […]
    let
      pkgs = nixpkgs.legacyPackages.${system};
      my-font = pkgs.stdenvNoCC.mkDerivation {
        pname = "my-font";
        version = "1.0.0";
        src = self;
        phases = [ "unpackPhase" "installPhase" ];
        installPhase = ''
          mkdir -p $out/share/fonts/truetype
          cp my-font.ttf $out/share/fonts/truetype
        '';
      };
      tex = pkgs.texlive.combine {
        inherit (pkgs.texlive) scheme-minimal latex-bin latexmk
        nicematrix fontspec;
      };
    in rec {
      # […]
{% endhighlight %}

Then, you can use the font just like a font from nixpkgs.
Actually, you want to have that font package in a separate flake, because if you set `src = self;` here, this derivation will unnecessarily be rebuilt every time anything in your repository changes.
You can refer to local flakes as inputs to your document flake if you don't want to publish the font flake.

Finally, if a font is available somewhere on the internet, you can either use `pkgs.fetchurl` to retrieve it when building, or declare it as input to your Nix Flake.

## Configurable Documents <span class="note">improved 2021-12-28</span>

Having a single document as output is fine for a lot of use-cases.
But what if our document has data inputs, for example because we want to generate bulk letters?
In this case, our output should not be the document itself, but a script that takes the relevant data as input and generates the document.
Let's try and modify our setup to do that.

The first step towards our goal is to have our package output a script that basically does what our build step currently does:
Build the document.
For this, we remove the *build* step from our package and modify the *install* step:

{% highlight nix %}
{
  description = "LaTeX Document Demo";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.05;
    flake-utils.url = github:numtide/flake-utils;
  };
  
  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib; eachSystem allSystems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      tex = pkgs.texlive.combine {
        inherit (pkgs.texlive) scheme-basic latexmk
        pgf nicematrix fontspec;
      };
    in rec {
      packages = {
        document = pkgs.stdenvNoCC.mkDerivation rec {
          name = "latex-demo-document";
          src = self;
          propagatedBuildInputs = [ pkgs.coreutils pkgs.fira-code tex ];
          phases = ["unpackPhase" "buildPhase" "installPhase"];
          SCRIPT = ''
            #!/bin/bash
            prefix=${builtins.placeholder "out"}
            export PATH="${pkgs.lib.makeBinPath propagatedBuildInputs}";
            DIR=$(mktemp -d)
            RES=$(pwd)/document.pdf
            cd $prefix/share
            mkdir -p "$DIR/.texcache/texmf-var"
            env TEXMFHOME="$DIR/.cache" \
                TEXMFVAR="$DIR/.cache/texmf-var" \
                OSFONTDIR=${pkgs.fira-code}/share/fonts \
              latexmk -interaction=nonstopmode -pdf -lualatex \
              -output-directory="$DIR" \
              -pretex="\pdfvariable suppressoptionalinfo 512\relax" \
              -usepretex document.tex
            mv "$DIR/document.pdf" $RES
            rm -rf "$DIR"
          '';
          buildPhase = ''
            printenv SCRIPT >latex-demo-document
          '';
          installPhase = ''
            mkdir -p $out/{bin,share}
            cp document.tex $out/share/document.tex
            cp latex-demo-document $out/bin/latex-demo-document
            chmod u+x $out/bin/latex-demo-document
          '';
        };
      };
      defaultPackage = packages.document;
    });
}
{% endhighlight %}

Mind how our `buildInputs` have moved to `propagatedBuildInputs`.
This is because these are now runtime dependencies and thus need to be part of the closure of the generated derivation.
That is achieved by putting them in the `propagatedBuildInputs`.

I put the script we output into a variable `SCRIPT`, which will be available as environment variable during our build.
Originally, I used `cat` with a HEREDOC to write the script, however that was horrible since all `$` that should be in the final script would have needed to be escaped.
Using `printenv` is far cleaner.
Note how we use `builtins.placeholder` to access the output directory since `$out` is a build-time variable and therefore not available in our script, which runs at runtime.
`builtins.placeholder` outputs the correct path at build time.

I removed `SOURCE_DATE_EPOCH` since when our derivation is a generator, we might want to use the actual generation date.
Since the PDF itself is not part of the derivation anymore, it is okay to generate different documents depending on the date; and the user can *still* set the variable when calling the generator to inject a custom date.

Our output directory now contains the generated script in `bin`, and `document.tex` in `share` as we need those files at runtime to build the document.
If you use any other local files (fonts, images, etc) in your document, you need to copy those as well.

Before, our build environment provided a temporary directory to build the document.
Now with our script, we don't have that anymore – the user may call the script from anywhere and that is our working directory then.
Therefore, we need to create a temporary directory manually via `mktemp -d` so that the current working directory is not cluttered with intermediate LaTeX files – the user only wants the resulting `.pdf` file.
This also ensures that any files existing in the working directory do not affect our build.

Fun fact: By explicitly depending on `pkgs.coreutils`, we circumvent a problem with `mktemp` that haunts macOS and BSD users:
The BSD `mktemp` requires a template as parameter, while the one in GNU coreutils does not.
This makes it [difficult to write a script that works with both versions](https://unix.stackexchange.com/questions/30091/fix-or-alternative-for-mktemp-in-os-x), a problem which we nicely circumvent by explicitly using the GNU coreutils everywhere.

Let's try it out:

{% highlight bash %}
git commit -a --amend --no-edit
nix build
result/bin/latex-demo-document
{% endhighlight %}

This should create the `document.pdf` in your working directory.
We can replace the last two commands with

{% highlight bash %}
nix run
{% endhighlight %}

Now that we can do this, let's make the document fillable with user-provided values.
`latexmk` provides a nice feature that executes TeX code before the main document.
We will set this up in our flake in a moment, for now let's assume the commands `\sender` and `\receiver` are available and update our `document.tex`:

{% highlight latex %}
\documentclass[a4paper]{article}

\usepackage{fontspec}
\setmonofont{Fira Code Light}

\usepackage{nicematrix}

\begin{document}
  \begin{NiceTabular}{p{5.5cm}|>{\ttfamily}p{2cm}}
  \CodeBefore
    \rowcolors{2}{white}{gray!30}
  \Body \hline
    Sender:    & \sender   \\ \hline
    Recipient: & \receiver \\ \hline
  \end{NiceTabular}
\end{document}
{% endhighlight %}

In our `flake.nix`, we now update the `latexmk` call to define those two commands:

{% highlight nix %}
{
  description = "LaTeX Document Demo";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.05;
    flake-utils.url = github:numtide/flake-utils;
  };
  
  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib; eachSystem allSystems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      tex = pkgs.texlive.combine {
        inherit (pkgs.texlive) scheme-basic latexmk
        pgf nicematrix fontspec;
      };
      # make variables more visible to defining them here
      vars = [ "sender" "receiver" ];
      # expands to definitions like \def\sender{$1}, i.e. each variable
      # will be set to the command line argument at the variable's position.
      texvars = toString
        (pkgs.lib.imap1 (i: n: ''\def\${n}{${"$" + (toString i)}}'') vars);
    in rec {
      packages = {
        document = pkgs.stdenvNoCC.mkDerivation rec {
          name = "latex-demo-document";
          src = self;
          propagatedBuildInputs = [ pkgs.coreutils pkgs.fira-code tex ];
          phases = ["unpackPhase" "buildPhase" "installPhase"];
          SCRIPT = ''
            #!/bin/bash
            prefix=${builtins.placeholder "out"}
            export PATH="${pkgs.lib.makeBinPath propagatedBuildInputs}";
            DIR=$(mktemp -d)
            RES=$(pwd)/document.pdf
            cd $prefix/share
            mkdir -p "$DIR/.texcache/texmf-var"
            env TEXMFHOME="$DIR/.cache" \
                TEXMFVAR="$DIR/.cache/texmf-var" \
                OSFONTDIR=${pkgs.fira-code}/share/fonts \
              latexmk -interaction=nonstopmode -pdf -lualatex \
              -output-directory="$DIR" \
              -pretex="\pdfvariable suppressoptionalinfo 512\relax${texvars}" \
              -usepretex document.tex
            mv "$DIR/document.pdf" $RES
            rm -rf "$DIR"
          '';
          buildPhase = ''
            printenv SCRIPT >latex-demo-document
          '';
          installPhase = ''
            mkdir -p $out/{bin,share}
            cp document.tex $out/share/document.tex
            cp latex-demo-document $out/bin/latex-demo-document
            chmod u+x $out/bin/latex-demo-document
          '';
        };
      };
      defaultPackage = packages.document;
    });
}
{% endhighlight %}

Now we can do:

{% highlight bash %}
git commit -a --amend --no-edit
nix run . Alice Bob
{% endhighlight %}

`nix run` expects as first argument the Flake to run, so if we provide parameters, we must put `.` first to reference the flake in our working directory.
This should give us a `document.pdf` containing the two given names.

By the way, if we ever push this repository to GitHub, e.g. at `example/nix-flakes-latex`, we can then run it anywhere via

{% highlight bash %}
nix run github:example/nix-flakes-latex Alice Bob
{% endhighlight %}

## Conclusion

Nix Flakes allow us not just to precisely specify *TeX Live* packages we need to build our document, but also to include external resources as additional dependencies.
By pinning the versions of our inputs in `flake.lock`, it guarantees us that the document can be reproducibly built anywhere.

Now you might wonder, what do we really *need* all this for?
Are LaTeX documents not like „write once, typeset, never touch the source again“?
Well, I'll have you know that I regularly build my pen & paper character sheets with LaTeX, they *are* fillable with values and *do* depend on external artwork.
The sources for that [are available on GitHub](https://github.com/flyx/DSA-4.1-Heldendokument) if you want to have a look, but be warned that everything is German.

Apart from that, I stumbled upon LaTeX code that just didn't want to compile with modern TeX Live more than once.
Using Nix Flakes also makes me feel safe enough to *not* commit the PDF file to the repository (just in case the source doesn't compile at some point in the future).

## Changelog

### 2021-12-28

 * Rewrote the section about fonts. Originally it described how to download a font from the internet and use it, but the more likely use-case would be to fetch fonts from nixpkgs.
   Therefore, the article now shows how to do that, and just mentions that you can also fetch one from some URL.
 * Also, use `OSFONTDIR` to tell LuaTeX where to find the font instead, which is more versatile than explicitly referencing a local path in the TeX source.
 * Instead of using `cat` and a HEREDOC to output a script, the code now uses an env variable which removes the need for crazy `$` escaping everywhere.

### 2021-11-30

 * Added section describing how to produce identical documents.