# PetriBSD: FreeBSD in a petri dish for study and manipulation

This work-in-progress set of scripts exists to explore FreeBSD build and upgrade techniques.

This toolkit requires a zpool, git-lite, and Internet access and by default uses /b as a build directory

Example Usage

Mirror FreeBSD MAIN repo on the zpool zroot:

```
sh mirror-MAIN.sh zroot
```

This can be periodically updated with:

```
git -C /b/MAIN remote update
```

The FreeBSD 13.0-RELEASE branch can be checked out with:

```
sh clone-13.0-RELEASE.sh zroot
```

Create a Golden Image with a zpool named gi-13.0-RELEASE based on a ggatel image named gi-13.0-RELEASE.raw to build to:

```
sh golden-image.sh zpool
```

Build each commit on the branch with a default of 10 commits for testing:

```
sh petribuild.sh -b 13.0-RELEASE -p zpool
```

This will use "OccamBSD" by default, which builds a minimum FreeBSD installation with root-on-OpenZFS and bootable under the bhyve hypervisor.

Build a 13.0-RELEASE virtual Machine image:

```
sh vm-image.sh -b 13.0-RELEASE
```

Install from the Golden Image to the Virtual Machine image named vm-13.0-RELEASE(.raw):

```
sh vm-install.sh -b 13.0-RELEASE
```

Export the configured Virtual Machine image:
```
sh vm-export.sh -b 
```

Prepare the host for bhyve booting (read and adjust the script as needed):
```
sh vm-prep.sh
```

Boot the Virtual Machine image at its most recent revision:
```
sh boot-vm-image.sh -b 13.0-RELEASE
```

1. Hopefully that boots

2. Many things are going on here:

* The VM is built with OccamBSD and is by definition minimalistic - changing the with_occam variable to 0 will preform a normal build
* "Meta Mode" is used for each build to achieve a delta bewteen builds
* "Reproductible Builds" are used for build consistency (needs love)
* The resuts of every build step are committed to a local Git repo for binary upgrade experiments
* It could be committed to SVN for use with svn-lite
* Some steps are performed on the first build for a "default" image
* The process provides many opportunities for configuration

3. There are various support scripts that are gradually receiving command line flags but many variables remain hard-coded

4. MFM = "Merge From Main", given that "stable" is not accurate.

Watch this space!

This is not an endorsement of GitHub
