/*
 * PackageManagerCache.vala
 *
 * Copyright 2012-2017 Tony George <teejeetech@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */

using GLib;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessHelper;
using TeeJee.System;
using TeeJee.Misc;

public class PackageManagerCache : GLib.Object {
	
	public LinuxDistro distro;
	public bool dry_run = false;
	
	public PackageManagerCache(LinuxDistro _distro, bool _dry_run){

		distro = _distro;

		dry_run = _dry_run;
	}

	// save -------------------------------------------

	public bool backup_cache(string basepath){

		string backup_cache = path_combine(basepath, "cache");

		string system_cache = "";

		if (!dry_run){
			dir_create(backup_cache);
		}

		switch(distro.package_manager){
		case "dnf":
			log_error("%s: %s".printf(Message.CACHE_NOT_SUPPORTED,"dnf"));
			return false;
			
		case "yum":
			log_error("%s: %s".printf(Message.CACHE_NOT_SUPPORTED,"yum"));
			return false;

		case "pacman":
			system_cache = "/var/cache/pacman/pkg";
			break;

		case "apt":
			system_cache = "/var/cache/apt/archives";
			break;

		default:
			log_error(Message.UNKNOWN_DISTRO);
			return false;
		}

		log_msg(_("Copying packages from cache..."));
	
		string cmd = "rsync -ai --numeric-ids";

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=lock --exclude=partial/ --exclude=apt-fast/";
		cmd += " '%s/'".printf(escape_single_quote(system_cache));
		cmd += " '%s/'".printf(escape_single_quote(backup_cache));

		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));

		if (dry_run){
			log_msg(_("Nothing to do (--dry-run mode)"));
			log_msg(string.nfill(70,'-'));
		}
		else{
			log_msg(Message.BACKUP_OK);
			log_msg(string.nfill(70,'-'));
		}
		
		return (status == 0);
	}

	// restore ---------------------------------------
	
	public bool restore_cache(string basepath){

		string backup_cache = path_combine(basepath, "cache");

		string system_cache = "";
		
		if (!dir_exists(backup_cache)){
			log_error("%s: %s".printf(_("Directory not found"), backup_cache));
			return false;
		}

		switch(distro.package_manager){
		case "dnf":
			log_error("%s: %s".printf(Message.CACHE_NOT_SUPPORTED,"dnf"));
			return false;
			
		case "yum":
			log_error("%s: %s".printf(Message.CACHE_NOT_SUPPORTED,"yum"));
			return false;

		case "pacman":
			system_cache = "/var/cache/pacman/pkg";
			break;

		case "apt":
			system_cache = "/var/cache/apt/archives";
			break;

		default:
			log_error(Message.UNKNOWN_DISTRO);
			return false;
		}

		log_msg(_("Copying packages to cache..."));
	
		string cmd = "rsync -ai --numeric-ids";

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=lock --exclude=partial/ --exclude=apt-fast/";
		cmd += " '%s/'".printf(escape_single_quote(backup_cache));
		cmd += " '%s/'".printf(escape_single_quote(system_cache));

		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));

		if (dry_run){
			log_msg(_("Nothing to do (--dry-run mode)"));
			log_msg(string.nfill(70,'-'));
		}
		else{
			log_msg(Message.RESTORE_OK);
			log_msg(string.nfill(70,'-'));
		}
		
		return (status == 0);
	}

	// clear -----------------------------------------
	
	public bool clear_cache(bool no_prompt){

		string cmd = "";
		
		switch(distro.package_manager){
			
		case "dnf":
			log_error("%s: %s".printf(Message.CACHE_NOT_SUPPORTED,"dnf"));
			return false;
			
		case "yum":
			log_error("%s: %s".printf(Message.CACHE_NOT_SUPPORTED,"yum"));
			return false;

		case "pacman":
			cmd = "pacman";
			
			if (no_prompt){
				cmd += " --noconfirm";
			}
			
			cmd = " -Sc";
			break;

		case "apt":
			cmd = "apt-get clean";
			break;

		default:
			log_error(Message.UNKNOWN_DISTRO);
			return false;
		}

		if (dry_run){
			log_msg(string.nfill(70,'-'));
			log_msg(_("Nothing to do (--dry-run mode)"));
			return true;
		}
		
		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));

		if (status == 0){
			log_msg(_("Removed packages from system cache"));
			log_msg(string.nfill(70,'-'));
		}

		return (status == 0);
	}
}
