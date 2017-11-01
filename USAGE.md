## Backup & Restore Actions

This page details the actions that are executed on backup and restore.

### Software Repositories

**Backup Actions**

Following actions are executed for backup:

1. Debian-based distros

   1. Launchpad PPA names are read from files in `/etc/apt/sources.list.d`. Names are saved to file `<basepath>/repos/launchpad-ppas.list`.  This file can be edited to comment-out or remove lines for unwanted repos.
   2. Third party PPAs are determined by reading list files in `/etc/apt/sources.list.d`. Source lines are saved to file `<basepath>/repos/<repo-name>.list`.  Files can be deleted from the backup folder for unwanted repos.
   3. Apt keys are exported to file `<basepath>/repos/apt.keys`

2. Fedora-based distros - Not supported

3. Arch-based distros   
   1. Custom repos are read from file `/etc/pacman.conf`. Source lines are saved to file `<basepath>/repos/<repo-name>.list`.  Files can be deleted from the backup folder for unwanted repos.
   2. Pacman keys are exported to file `<basepath>/repos/pacman.keys`

**Restore Actions**

Following actions are executed for restore:

1. Debian-based distros
   1. Missing Launchpad PPAs are added using command `add-apt-repository`
   2. Third party PPAs are installed by copying list file from backup folder to `/etc/apt/sources.list.d`
   3. Apt keys are imported from file `<basepath>/repos/pacman.keys`
   4. Package information is updated by running `apt update`
2. Fedora-based distros
   1. Restoring repos is not supported.
   2. Package information is updated by running `dnf check-update`	
3. Arch-based distros 
   2. Custom repos are installed by appending the source lines to `/etc/pacman.conf`
   3. Pacman keys are imported from file `<basepath>/repos/pacman.keys`
   4. Package information is updated by running `pacman -Sy`

### Downloaded Packages

**Backup Actions**

Following actions are executed for backup:
1. Downloaded packages are copied from system cache to backup location `<basepath>/cache` using `rsync` command
   * Debian-based distros - Copied from `/var/cache/apt/archives`
   * Fedora-based distros - Not supported
   * Arch-based distros - Copied from `/var/cache/pacman/pkg`


**Restore Actions**

Following actions are executed for restore:

1. Packages are copied from backup location to system cache using `rsync`

### Installed Packages

**Backup Actions**

Following actions are executed for backup:

1. List of installed packages are saved to `<basepath>/packages/installed.list`. This file is saved only for reference and is not used during restore.

2. List of installed packages are filtered to **remove** the following:

   1. Kernel packages - `linux-headers*`, `linux-signed*`, `linux-tools*`
   2. Packages that were auto-installed as dependencies for other packages. 
      * Debian-based distros - Determined using `aptitude` and will be filtered out
      * Other distros - Cannot be determined and will not be filtered out
   3. Packages that are part of the Linux distribution base.
      * Debian-based - Determined by reading `/var/log/installer/initial-status.gz` and will be filtered out. Cannot be determined if this file is missing on the system.
      * Other distros - Cannot be determined and will not be filtered out

   List of filtered packages are saved to `<basepath>/packages/selected.list`. This file can be edited to comment-out or remove lines for unwanted packages.

**Restore Actions**

Following actions are executed for restore:
   1. List of packages are read from `<basepath>/packages/selected.list`. Packages that are not installed, but available in repositories, will be installed using the package manager.
      * Debian-based distros - Installed using `aptitude`, `apt-fast`, `apt-get` or `apt` in order of preference
      * Fedora-based distros - Installed using `dnf` or `yum` in order of preference
      * Arch-based distros - Installed using `pacman`

   2. Debian-based distros - Any deb files in backup folder `<basepath>/debs` will be installed using `apt` or `gdebi` in order of preference.


### Users & Groups

**Backup Actions**

Following actions are executed for backup:

1. Entries in `/etc/passwd` and `/etc/shadow` are saved to backup folder  `<basepath>/users` for human users (UID = 0 or UID >= 1000 and UID != 65534). User's line in both files are saved as `<username>.passwd` and `<username>.shadow` in the backup folder. You can delete the files for any users that you do not wish to restore.
2. Entries in `/etc/group` and `/etc/gshadow` are saved to backup folder  `<basepath>/groups` for non-system groups (GID >= 1000 and GID != 65534). Group's line in both files are saved as `<groupname>.group` and `<groupname>.gshadow` in the backup folder. You can delete the files for any groups that you do not wish to restore.
3. For all groups, the list of users in the group are saved in file `<basepath>/groups/memberships.list`.

**Restore Actions**

Following actions are executed for restore:

1. *Missing users* are added from backup folder `<basepath>/users`
   1. Missing users are added using `useradd` command
   2. User's full name, home directory path, and other fields are updated in `/etc/passwd`. User's UID will not be updated and remains same as the value generated by `useradd` command.
   3. User's password field and password expiry rules are updated in `/etc/shadow`

2. *Missing groups* are added from backup folder `<basepath>/groups`

   1. Missing users are added using `groupadd` command
   2. Group's password and users field are updated in `/etc/group`. Group's GID will not be updated and remains same as the value generated by `groupadd` command.
   3. Group's password, admin and member fields are updated in `/etc/gshadow`

3. *Missing members* are added to groups

   1. Missing members are added to groups by reading the file `<basepath>/groups/memberships.list`. Members are added directly by updating `/etc/group`


