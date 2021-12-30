## Setup

Create an empty directory, this will be the directory of our main application.
In it, do:

{% highlight plain %}
mkdir -p externals/simple-plugin
git init
{% endhighlight %}

Since we do not want to set up multiple repositories on some Git hoster, we'll use the `externals` directory to simulate external repositories.
We will never reference `externals` as if it was a local directory; it will only ever be referenced in Flake inputs.
As with any Nix Flake, we need all files processed by Nix to be checked in to version control, which is why we `git init`.

We'll be using Go modules, so do this in the main directory:

{% highlight bash %}
nix run nixpkgs#go mod init "mainapp"
{% endhighlight %}

This will give us a `go.mod` file.
Now, let's write a simple main application in `main.go`:

{{main.go}}

To finish the main application, we provide it with a `flake.nix`:

{{flake.nix}}

For `vendorSha256` just supply `pkgs.lib.fakeSha256` initially and then build once.
Then, update the value to be the one that was expected as given in the error message.

We use `nix-filter` to explicitly exclude the externals from the sources of the main app, and also the `flake.nix` which is something sensible to do.
If we don't exclude `flake.nix`, any change there would trigger a rebuild even if it was unnecessary.
Mind that `nix-filter` doesn't work on `self` so you need to give `./.`.

Now, create the `flake.lock`, check in everything, and run it:

{% highlight bash %}
nix flake update
git add flake.* go.mod main.go
git commit -a -m "initial commit"
nix run
{% endhighlight %}

(Committing is optional, but saves us from a warning that the repository is dirty.)
This should give us:

{% highlight plain %}
Hello, world!
The following plugins are available: []
{% endhighlight %}

Let's recap what we have here:

 * Our flake supplies the function `lib.buildApp`.
 * That function builds our app from the supplied `pkgs` and a list of `plugins`.
   The plugin list isn't used for anything yet during the build.
 * Our flake also supplies a package built with `buildApp` with an empty plugin list.
