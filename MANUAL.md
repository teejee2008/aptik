## Aptik NG - User Manual

```
Usage: aptik <command> [options]

▰▰▰ Software Repositories ▰▰▰

Commands:
  --list-repos                   List software repositories
  --backup-repos                 Save list of software repositories
  --restore-repos                Add missing software repositories from backup
  --import-missing-keys          Find and import missing keys for apt repos

Supports: apt (Debian & Derivatives), pacman (Arch & Derivatives),
dnf/yum (Fedora & Derivatives)

▰▰▰ Downloaded Packages ▰▰▰

Commands:
  --backup-cache                 Copy downloaded packages from system cache
  --restore-cache                Copy packages to system cache from backup
  --clear-cache                  Remove downloaded packages from system cache

Supports: apt (Debian & Derivatives), pacman (Arch & Derivatives)

▰▰▰ Installed Software ▰▰▰

Commands:
  --list-installed               List installed packages
  --list-available               List available packages
  --list-foreign                 List non-native packages
  --list-extra                   List extra packages installed by user
  --list-{default|dist|base}     List default packages for linux distribution
  --backup-packages              Save list of installed packages
  --restore-packages             Install missing packages from backup

Supports: apt (Debian & Derivatives), pacman (Arch & Derivatives),
dnf/yum (Fedora & Derivatives)

▰▰▰ User Accounts ▰▰▰

Commands:
  --list-users                   List users
  --list-users-all               List all users (including system user accounts)
  --backup-users                 Backup users
  --restore-users                Restore users from backup

▰▰▰ Groups ▰▰▰

Commands:
  --list-groups                  List groups
  --list-groups-all              List all groups (including system groups)
  --backup-groups                Backup groups
  --restore-groups               Restore groups from backup

▰▰▰ Home Directory Data ▰▰▰

Commands:
  --backup-home                  Backup data in users' home directories
  --restore-home                 Restore data in users' home directories from backup
  --fix-ownership                Updates ownership for users' home directory contents

Options:
  --users <usr1,usr2,..>         Users to backup and restore
                                 default: all users

  --duplicity                    Use duplicity for backup instead of TAR
                                 default: TAR

  --password <string>            Password for encryption/decryption with duplicity
                                 default: 'aptik'

  --full                         Do full backup with duplicity
                                 default: incremental if backup exists, else full

  --exclude-hidden               Exclude hidden files and directories (app configs)
                                 default: include

▰▰▰ Mount Entries ▰▰▰

Commands:
  --list-mounts                  List /etc/fstab and /etc/crypttab entries
  --backup-mounts                Backup /etc/fstab and /etc/crypttab entries
  --restore-mounts               Restore /etc/fstab and /etc/crypttab entries from backup

▰▰▰ Dconf Settings ▰▰▰

Commands:
  --list-dconf                   List dconf settings changed by user
  --backup-dconf                 Backup dconf settings changed by user
  --restore-dconf                Restore dconf settings from backup

Options:
  --users <usr1,usr2,..>         Users to backup and restore
                                 default: all users

▰▰▰ Scheduled Tasks ▰▰▰

Commands:
  --list-cron                    List cron tasks
  --backup-cron                  Backup cron tasks
  --restore-cron                 Restore cron tasks

Options:
  --users <usr1,usr2,..>         Users to backup and restore
                                 default: all users

▰▰▰ All Items ▰▰▰

Commands:
  --backup-all                   Backup all items
  --restore-all                  Restore all items from backup
  --remove-all                   Remove all items from backup

▰▰▰ Common ▰▰▰

Options:
  --basepath <dir>               Backup directory (default: current directory)
  --scripted                     Run in non-interactive mode
  --dry-run                      Simulate actions for --restore commands
  --help                         Show all options
  
```

### One-line Backup & Restore

> `aptik --backup-all` and `aptik --restore-all` are one-line commands for taking a backup of your system and restoring it on a new system. You can safely use these 2 commands and skip the rest of this document, if you are not interested in knowing the details of backup and restore steps.

#### Backup

Usage: `aptik --backup-all`

This will backup all items listed in the sections below. Backups are saved in current directory unless `--basepath <path>` is specified.

#### Restore

Usage: `aptik --restore-all`

This will restore all items listed in the sections below. Backups are restored from current directory unless `--basepath <path>` is specified.

#### Remove

Usage: `aptik --remove-all`

This will remove all backups in backup folder that were created by Aptik.

> Backups are saved and restored from current working directory unless `--basepath <path>` is specified.

### Software Repositories

#### Backup

Usage: `aptik --backup-repos`

Following actions are executed for backup:

1. Debian-based distros

   1. Launchpad PPA names are read from files in `/etc/apt/sources.list.d`. Names are saved to file `<basepath>/repos/launchpad-ppas.list`.  This file can be edited to comment-out or remove lines for unwanted repos.
   2. Third party PPAs are determined by reading list files in `/etc/apt/sources.list.d`. Source lines are saved to file `<basepath>/repos/<repo-name>.list`.  Files can be deleted from the backup folder for unwanted repos.
   3. Apt keys are exported to file `<basepath>/repos/apt.keys`

2. Fedora-based distros - Not supported

3. Arch-based distros   
   1. Custom repos are read from file `/etc/pacman.conf`. Source lines are saved to file `<basepath>/repos/<repo-name>.list`.  Files can be deleted from the backup folder for unwanted repos.
   2. Pacman keys are exported to file `<basepath>/repos/pacman.keys`

#### Restore

Usage: `aptik --restore-repos`

Following actions are executed for restore:

1. Debian-based distros
   1. Missing Launchpad PPAs are added using command `add-apt-repository`
   2. Third party PPAs are installed by copying list file from backup folder to `/etc/apt/sources.list.d`. If the repo source lines contain release codename (trusty, xenial, etc), and codename does not match current system, then it will be skipped.
   3. Apt keys are imported from file `<basepath>/repos/pacman.keys`
   4. Package information is updated by running `apt update`
2. Fedora-based distros
   1. Restoring repos is not supported.
   2. Package information is updated by running `dnf check-update`
3. Arch-based distros 
   1. Custom repos are installed by appending the source lines to `/etc/pacman.conf`
   2. Pacman keys are imported from file `<basepath>/repos/pacman.keys`
   3. Package information is updated by running `pacman -Sy`

### Downloaded Packages

#### Backup

Usage: `aptik --backup-cache`

Following actions are executed for backup:

1. Downloaded packages are copied from system cache to backup location `<basepath>/cache` using `rsync` command
   * Debian-based distros - Copied from `/var/cache/apt/archives`
   * Fedora-based distros - Not supported
   * Arch-based distros - Copied from `/var/cache/pacman/pkg`


#### Restore

Usage: `aptik --restore-cache`

Following actions are executed for restore:

1. Packages are copied from backup location to system cache using `rsync`

### Installed Packages

#### Backup

Usage: `aptik --backup-packages`

Following actions are executed for backup:

1. List of installed packages are saved to `<basepath>/packages/installed.list`. This file is saved only for reference and is not used during restore.

2. List of installed packages are filtered to **remove** the following:

   *  Kernel packages - `linux-headers*`, `linux-signed*`, `linux-tools*`, `linux-image*`
   *  Library packages - `lib*` - These are usually dependencies for other software and will be installed automatically if needed.
   *  Non-native (foreign) packages. For example,  `i386` packages on an `amd64` system. Can be included in list with option `--include-foreign` but not recommended to include.
   *  Theme packages - `*-theme` are excluded if option `--exclude-themes` is specified. You can use this option if you restore themes using command `--restore-themes`, and do not wish to receive updates for the packages.
   *  Icon theme packages - `*-icon-theme` are excluded if option `--exclude-icons` is specified. You can use this option if you restore icon themes using command `--restore-icons`, and do not wish to receive updates for the packages.
   *  Font packages - `fonts-*` are excluded if option `--exclude-fonts` is specified. You can use this option if you restore fonts using command `--restore-fonts`, and do not wish to receive updates for the packages.
   *  Packages that were auto-installed as dependencies for other packages. 
      * *Debian-based distros* - Determined using `aptitude` and will be filtered out
      * *Other distros* - Cannot be determined and will not be filtered out
   *  Packages that are part of the Linux distribution base.
      * *Debian-based* - Determined by reading `/var/log/installer/initial-status.gz` and will be filtered out. Cannot be determined if this file is missing on the system.
      * *Other distros* - Cannot be determined and will not be filtered out

3. List of filtered packages are saved to `<basepath>/packages/selected.list`. This file can be further edited to comment-out or remove lines for unwanted packages.

#### Restore

Usage: `aptik --restore-packages`

Following actions are executed for restore:
   1. List of packages are read from `<basepath>/packages/selected.list`. Packages that are not installed, but available in repositories, will be installed using the package manager.
      * Debian-based distros - Installed using `aptitude`, `apt-fast`, `apt-get` or `apt` in order of preference
      * Fedora-based distros - Installed using `dnf` or `yum` in order of preference
      * Arch-based distros - Installed using `pacman`

   2. Debian-based distros - Any deb files in backup folder `<basepath>/debs` will be installed using `apt` or `gdebi` in order of preference.


### User Accounts

#### Backup

Usage: `aptik --backup-users`

Following actions are executed for backup:

1. Entries in `/etc/passwd` and `/etc/shadow` are saved to backup folder  `<basepath>/users` for human users (UID = 0 or UID >= 1000 and UID != 65534). User's line in both files are saved as `<username>.passwd` and `<username>.shadow` in the backup folder. You can delete the files for any users that you do not wish to restore.

#### Restore

Usage: `aptik --restore-users`

Following actions are executed for restore:

1. *Missing users* are added from backup folder `<basepath>/users`
   1. Missing users are added using `useradd` command
   2. User's full name, home directory path, and other fields are updated in `/etc/passwd`. User's UID will not be updated and remains same as the value generated by `useradd` command.
   3. User's password field and password expiry rules are updated in `/etc/shadow`



### User Groups

#### Backup

Usage: `aptik --backup-groups`

Following actions are executed for backup:

1. Entries in `/etc/group` and `/etc/gshadow` are saved to backup folder  `<basepath>/groups` for non-system groups (GID >= 1000 and GID != 65534). Group's line in both files are saved as `<groupname>.group` and `<groupname>.gshadow` in the backup folder. You can delete the files for any groups that you do not wish to restore.
2. For all groups, the list of users in the group are saved in file `<basepath>/groups/memberships.list`.

#### Restore

Usage: `aptik --restore-groups`

Following actions are executed for restore:

1. *Missing groups* are added from backup folder `<basepath>/groups`
   1. Missing users are added using `groupadd` command
   2. Group's password and users field are updated in `/etc/group`. Group's GID will not be updated and remains same as the value generated by `groupadd` command.
   3. Group's password, admin and member fields are updated in `/etc/gshadow`
2. *Missing members* are added to groups
   1. Missing members are added to groups by reading the file `<basepath>/groups/memberships.list`. Members are added directly by updating `/etc/group`

### Home Directory Data

#### Backup

Usage: `aptik --backup-home`

Following actions are executed for backup:

1. For each user, the contents of home directory are archived using TAR + GZIP and saved to file  `<basepath>/home/<username>/data.tar.gz`. Full backup is created every time a backup is taken.

2. Backups can be created for specific users with option `--users <user1,user2...>`. Specify a comma-separated list of user logins without space.

3. Some directories are excluded by default to save space and avoid issues after restore.

   ```
   ~/.thumbnails
   ~/.cache
   ~/.dbus
   ~/.gvfs
   ~/.config/dconf/user
   ~/.local/share/Trash
   ~/.local/share/trash
   ~/.mozilla/firefox/*.default/Cache
   ~/.mozilla/firefox/*.default/OfflineCache
   ~/.opera/cache
   ~/.kde/share/apps/kio_http/cache
   ~/.kde/share/cache/http
   ```

4. Hidden files and folders in home directories can be excluded with option `--exclude-hidden` . These files and folders contain *user-specific application and system settings*. These can be excluded if you wish to only migrate your data, without migrating your application settings. Its recommended to keep these files and folders since they contain configuration changes that users have made to different applications.

#### Restore

Usage: `aptik --restore-home`

Following actions are executed for restore:

1. For each user, the TAR file backup `<basepath>/home/<username>/data.tar.gz` is extracted to the user's home directory. Files are restored to original locations along with original permissions and timestamps.
2. For each user, the ownership is updated for file and folders in user's home directory. This ensures that all files in home directory are owned by the user.
3. Backups can be restored for specific users with option `--users <user1,user2...>`. Specify a comma-separated list of user names without space.

### DConf Settings

dconf database stores application settings for users. Aptik can backup and restore any changes that were made to default settings. The changes are applied over default settings on the new system.

Note: The dconf database is present as a single file `~/.config/dconf/user` in each users' home directory. This file will be excluded when taking backup of user's home directories.

#### Backup

Usage: `aptik --backup-dconf`

Following actions are executed for backup:

1. For each user, dconf settings that are different from defaults are dumped to backup file `<basepath>/dconf/<username>/dconf.settings`

#### Restore

Usage: `aptik --restore-dconf`

Dconf settings can be restored only when users are logged-in. The restore operation will copy backup files to each user's home directory and create an autostart entry to restore settings on first user login.

Following actions are executed for restore:

1. Backup file `<basepath>/dconf/<username>/dconf.settings` will be copied to the user's home directory -  `$HOME/.config/aptik/dconf.settings`

2. A script is created which will restore the settings from backup file when executed:

    `$HOME/.config/aptik/restore-dconf.sh`

3. An autostart entry is created at path `$HOME/.config/autostart/aptik_restore-dconf.desktop` which will launch the script after user login.

4. The script will restore the dconf settings and delete the autostart entry when it executes on the first user login.



Note: We are migrating only those settings that were changed by user on previous system. It will be applied over the default settings on new system.

### Scheduled Tasks (Cron Jobs)

#### Backup

Usage: `aptik --backup-cron`

Following actions are executed for backup:

1. For each user, crontab entries are dumped to backup file `<basepath>/cron/<username>.crontab`
2. Script files in system directories `/etc/cron.*` are saved to backup folders `<basepath>/cron/cron.*`

#### Restore

Usage: `aptik --restore-cron`

Following actions are executed for restore:

1. For each user, crontab file is replaced from backup file `<basepath>/cron/<username>.crontab`. 
2. Script files are copied from backup folders  `<basepath>/cron/cron.*` to system directories `/etc/cron.*` 
3. Permissions are updated to 644 for files in folder `/etc/cron.d`
4. Permissions are updated to 755 for files in folder `/etc/cron.{daily,hourly,monthly,weekly}`

### Mount Entries (fstab and crypttab entries)

#### Backup

Usage: `aptik --backup-mounts`

Following actions are executed for backup:

1. Entries in `/etc/fstab` and `/etc/crypttab` are saved to backup folder  `<basepath>/mounts` . Entries are saved individually as `<dev-name>_<mount-point>.fstab` and `<dev-name>_<mount-point>.crypttab` in the backup folder. You can delete the files for any mount entries that you do not wish to restore.
2. Device names like `/dev/sda1` and `/dev/mapper/sd2_crypt` will be replaced by UUIDs like `UUID=576be21b-3c3a-4287-b971-40b8e8b39823` while saving backup files. This makes the entries portable so that they can be used on other systems where the device names may be different.

#### Restore

Usage: `aptik --restore-mounts`

Following actions are executed for restore:

1. Backups are created for  `/etc/fstab` and `/etc/crypttab` by moving existing files to  `/etc/fstab.bkup.<timestamp>` and `/etc/crypttab.bkup.<timestamp>`
2. fstab file has following fields - `<file_system> <mount_point> <fstype> <options> <dump> <pass>`. Fields `<file_system> <mount_point> <fstype> <dump> <pass>` will remain unchanged for existing entries in `/etc/fstab`.
3. If a backup entry exists for same `<mount_point>` and same `<fstype>` field, then field `<options>` will be replaced from backup entry.
4. *New entries* in backup folder are *added* to `/etc/fstab` and `/etc/crypttab` .  New entries are determined by comparing field `<mount_point>`
5. New entries for system mount points - `/`,  `/boot`, `/boot/efi` and  `/home` - will **not** be added to `/etc/fstab` since these are system specific, and not applicable to the new system where restore is being executed. Existing entries if any will remain unchanged.
6. All entries are sorted on mount point field before the fstab file is written to disk. This ensures that base mount paths are populated before mounting subdirectories.
7. New entries added to `/etc/crypttab` will have `nofail` appended to `<options>` if not already present. This allows the system to boot successfully even if device is missing at boot time.
8. It's recommended to **review changes** before rebooting the system. Run `sudo aptik --list-mounts` to view updated entries after restore completes. Replace the backup files in case of any issues - `/etc/fstab.bkup.<timestamp>` and `/etc/crypttab.bkup.<timestamp>`.

