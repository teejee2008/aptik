/*
 * MountEntryManager.vala
 *
 * Copyright 2017 Tony George <teejeetech@gmail.com>
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

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessHelper;
using TeeJee.Misc;

public class MountEntryManager : BackupManager {

	public Gee.ArrayList<FsTabEntry> fstab = new Gee.ArrayList<FsTabEntry>();
	
	public Gee.ArrayList<CryptTabEntry> crypttab = new Gee.ArrayList<CryptTabEntry>();

	public MountEntryManager(LinuxDistro _distro, User _current_user, string _basepath, bool _dry_run, bool _redist, bool _apply_selections){

		base(_distro, _current_user, _basepath, _dry_run, _redist, _apply_selections, "mounts");
	}

	// query -----------------------------------
	
	public void query_mount_entries(){

		read_fstab_file();

		read_crypttab_file();

		update_device_uuids();
	}

	public bool read_fstab_file(){

		string tab_file = "/etc/fstab";

		if (!file_exists(tab_file)){
			log_error("%s: %s".printf(Messages.FILE_MISSING, tab_file));
			return false;
		}
		
		string txt = file_read(tab_file);
		
		foreach(string line in txt.split("\n")){
			
			parse_fstab_line(line);
		}

		return true;
	}

	public bool read_crypttab_file(){

		string tab_file = "/etc/crypttab";

		if (!file_exists(tab_file)){
			log_error("%s: %s".printf(Messages.FILE_MISSING, tab_file));
			return false;
		}
		
		string txt = file_read(tab_file);
		
		foreach(string line in txt.split("\n")){

			parse_crypttab_line(line);
		}

		return true;
	}

	public void read_mount_entries_from_folder(string backup_path){

		var list = dir_list_names(backup_path, true);
		
		foreach(string backup_file in list){

			string file_name = file_basename(backup_file);

			if (!file_name.has_suffix(".fstab")){ continue; }

			parse_fstab_line(file_read(backup_file)); 
		}

		foreach(string backup_file in list){

			string file_name = file_basename(backup_file);

			if (!file_name.has_suffix(".crypttab")){ continue; }

			parse_crypttab_line(file_read(backup_file));
		}

		update_device_uuids();

		log_debug("read_mount_entries_from_folder(): %d, %d".printf(fstab.size, crypttab.size));
	}

	private void parse_fstab_line(string line){
		
		if ((line == null) || (line.length == 0)){ return; }

		if (line.strip().has_prefix("#")){ return; }
		
		FsTabEntry entry = null;

		//<device> <mount point> <type> <options> <dump> <pass>
		
		var match = regex_match("""([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)""", line);

		if (match != null){
			
			entry = new FsTabEntry();
			
			entry.device = match.fetch(1);
			entry.mount_point = match.fetch(2);
			entry.fs_type = match.fetch(3);
			entry.options = match.fetch(4);
			entry.dump = match.fetch(5);
			entry.pass = match.fetch(6);
			
			fstab.add(entry);
		}
	}

	private void parse_crypttab_line(string line){
		
		if ((line == null) || (line.length == 0)){ return; }

		if (line.strip().has_prefix("#")){ return; }
		
		CryptTabEntry entry = null;

		//<name> <device> <password> <options>
		
		var match = regex_match("""([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)""", line);

		if (match != null){
			
			entry = new CryptTabEntry();
			
			entry.name = match.fetch(1);
			entry.device = match.fetch(2);
			entry.password = match.fetch(3);
			entry.options = match.fetch(4);
			
			crypttab.add(entry);
		}
	}

	private void update_device_uuids(){
		
		var devices = Device.get_block_devices();
		
		foreach(var entry in fstab){

			if (!entry.device.up().contains("UUID=") && !entry.device.down().has_prefix("/dev/disk/")){

				var dev = Device.find_device_in_list_by_name(devices, entry.device);
				if ((dev != null) && (dev.uuid.length > 0)){
					entry.device = "UUID=%s".printf(dev.uuid);
				}
			}
		}

		foreach(var entry in crypttab){

			if (!entry.device.up().contains("UUID=") && !entry.device.down().has_prefix("/dev/disk/")){

				var dev = Device.find_device_in_list_by_name(devices, entry.device);
				if ((dev != null) && (dev.uuid.length > 0)){
					entry.device = "UUID=%s".printf(dev.uuid);
				}
			}
		}
	}
	
	public static bool save_fstab_file(Gee.ArrayList<FsTabEntry> list){
		
		string txt = "# <file system> <mount point> <type> <options> <dump> <pass>\n\n";

		bool found_root = false;
		
		var tmplist = new Gee.ArrayList<Gee.ArrayList<string>>();

		foreach(var ent in list){
			
			var lent = new Gee.ArrayList<string>();
			tmplist.add(lent);
			
			lent.add(ent.device);
			lent.add(ent.mount_point);
			lent.add(ent.fs_type);
			lent.add(ent.options);
			lent.add(ent.dump);
			lent.add(ent.pass);

			if (ent.mount_point == "/"){
				found_root = true;
			}
		}

		txt += format_columns(tmplist);

		// ------------------------------------------------------

		if (found_root){

			var t = Time.local (time_t ());

			string file_path = "/etc/fstab";
		
			string cmd = "mv -vf %s %s.bkup.%s".printf(file_path, file_path, t.format("%Y-%d-%m_%H-%M-%S"));
			Posix.system(cmd);
		
			bool ok = file_write(file_path, txt);

			if (ok){ log_msg("%s: %s".printf(_("Saved"), file_path)); }
			
			return ok;
		}
		else{
			log_error(_("Critical: New fstab does not have entry for root mount point (!). Existing file will not be changed."));
		}

		return false;
	}

	public static bool save_crypttab_file(Gee.ArrayList<CryptTabEntry> list){
		
		string txt = "# <target name> <source device> <key file> <options>\n\n";

		var tmplist = new Gee.ArrayList<Gee.ArrayList<string>>();

		foreach(var ent in list){
			
			var lent = new Gee.ArrayList<string>();
			tmplist.add(lent);

			lent.add(ent.name);
			lent.add(ent.device);
			lent.add(ent.password);
			lent.add(ent.options);
		}

		txt += format_columns(tmplist);

		// ------------------------------------------------------
		
		var t = Time.local (time_t ());

		string file_path = "/etc/crypttab";
		
		string cmd = "mv -vf %s %s.bkup.%s".printf(file_path, file_path, t.format("%Y-%d-%m_%H-%M-%S"));
		Posix.system(cmd);
		
		bool ok = file_write(file_path, txt);

		if (ok){ log_msg("%s: %s".printf(_("Saved"), file_path)); }
		
		return ok;
	}

	// list ----------------------

	public void dump_info(){

		string txt = "";

		foreach(var entry in fstab){

			bool is_system = false;
			
			switch (entry.mount_point){
			case "/":
			case "/home":
			case "/boot":
			case "/boot/efi":
				is_system = true;
				break;
			}

			txt += "NAME='%s'".printf(entry.mount_point);
			txt += ",DEV='%s'".printf(entry.device);
			txt += ",MPATH='%s'".printf(entry.mount_point);
			txt += ",FS='%s'".printf(entry.fs_type);
			txt += ",OPT='%s'".printf(entry.options);
			txt += ",DUMP='%s'".printf(entry.dump);
			txt += ",PASS='%s'".printf(entry.pass);
			txt += ",ACT='%s'".printf(is_system ? "0" : "1");
			txt += ",SENS='%s'".printf(is_system ? "0" : "1");
			txt += ",TYPE='%s'".printf("fstab");
			txt += "\n";
		}

		foreach(var entry in crypttab){

			txt += "NAME='%s'".printf(entry.name);
			txt += ",DEV='%s'".printf(entry.device);
			txt += ",PASSWORD='%s'".printf(entry.password);
			txt += ",OPT='%s'".printf(entry.options);
			txt += ",ACT='%s'".printf("1");
			txt += ",SENS='%s'".printf("1");
			txt += ",TYPE='%s'".printf("crypttab");
			txt += "\n";
		}
		
		log_msg(txt);
	}

	public void dump_info_backup(){

		if (!dir_exists(files_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, files_path);
			log_error(msg);
			return;
		}

		this.query_mount_entries();

		var mgr = new MountEntryManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.read_mount_entries_from_folder(files_path);
		
		var fstab_bkup = mgr.fstab;
		var crypttab_bkup = mgr.crypttab;
		
		string txt = "";

		foreach(var entry in fstab_bkup){

			bool is_system = false;
			
			switch (entry.mount_point){
			case "/":
			case "/home":
			case "/boot":
			case "/boot/efi":
				is_system = true;
				break;
			}

			bool is_installed = false;
			foreach(var ent in fstab){
				if (ent.mount_point == entry.mount_point){
					is_installed = true;
					break;
				}
			}

			txt += "NAME='%s'".printf(entry.mount_point);
			txt += ",DEV='%s'".printf(entry.device);
			txt += ",MPATH='%s'".printf(entry.mount_point);
			txt += ",FS='%s'".printf(entry.fs_type);
			txt += ",OPT='%s'".printf(entry.options);
			txt += ",DUMP='%s'".printf(entry.dump);
			txt += ",PASS='%s'".printf(entry.pass);
			txt += ",ACT='%s'".printf((is_system || is_installed) ? "0" : "1");
			txt += ",SENS='%s'".printf((is_system || is_installed) ? "0" : "1");
			txt += ",INST='%s'".printf(is_installed ? "1" : "0");
			txt += ",TYPE='%s'".printf("fstab");
			txt += "\n";
		}

		foreach(var entry in crypttab_bkup){

			bool is_installed = false;
			foreach(var ent in crypttab){
				if (ent.name == entry.name){
					is_installed = true;
					break;
				}
			}
			
			txt += "NAME='%s'".printf(entry.name);
			txt += ",DEV='%s'".printf(entry.device);
			txt += ",PASSWORD='%s'".printf(entry.password);
			txt += ",OPT='%s'".printf(entry.options);
			txt += ",ACT='%s'".printf(is_installed ? "0" : "1");
			txt += ",SENS='%s'".printf(is_installed ? "0" : "1");
			txt += ",INST='%s'".printf(is_installed ? "1" : "0");
			txt += ",TYPE='%s'".printf("crypttab");
			txt += "\n";
		}
		
		log_msg(txt);
	}

	public void list_mount_entries(){

		log_msg("/etc/fstab :\n");

		fstab.sort((a,b)=>{ return strcmp(a.mount_point, b.mount_point); });
		
		string txt = "# <file system> <mount point> <type> <options> <dump> <pass>\n\n";

		var tmplist = new Gee.ArrayList<Gee.ArrayList<string>>();

		foreach(var ent in fstab){
			
			var lent = new Gee.ArrayList<string>();
			tmplist.add(lent);
			
			lent.add(ent.device);
			lent.add(ent.mount_point);
			lent.add(ent.fs_type);
			lent.add(ent.options);
			lent.add(ent.dump);
			lent.add(ent.pass);
		}

		txt += format_columns(tmplist);

		log_msg(txt);

		log_msg(string.nfill(70,'-'));

		// -------------------------------------------------------

		log_msg("/etc/crypttab :\n");

		crypttab.sort((a,b)=>{ return strcmp(a.name, b.name); });

		txt = "# <target name> <source device> <key file> <options>\n\n";

		tmplist = new Gee.ArrayList<Gee.ArrayList<string>>();

		foreach(var ent in crypttab){
			
			var lent = new Gee.ArrayList<string>();
			tmplist.add(lent);

			lent.add(ent.name);
			lent.add(ent.device);
			lent.add(ent.password);
			lent.add(ent.options);
		}

		txt += format_columns(tmplist);

		log_msg(txt);
		
		log_msg(string.nfill(70,'-'));
	}

	// backup ----------------------------------
	
	public bool backup_mount_entries(){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_MOUNTS));
		log_msg(string.nfill(70,'-'));
		
		init_backup_path();

		read_selections();
		
		bool status = true;

		foreach(var entry in fstab){

			if (redist && entry.is_normal_device_mount()){
				continue;
			}

			if (exclude_list.contains(entry.mount_point)){ continue; }

			switch (entry.mount_point){
			case "/":
			case "/home":
			case "/boot":
			case "/boot/efi":
				continue; // it's too risky to migrate these entries
			}

			//string backup_file = path_combine(backup_path, "%s %s.fstab".printf(entry.device.replace("/","╱"), entry.mount_point.replace("/","╱")));
			string backup_file = path_combine(files_path, "%s.fstab".printf(entry.mount_point.replace("/","_")));
			bool ok = file_write(backup_file, entry.get_line());
			chmod(backup_file, "a+rw");
			
			if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file)); }
			else{ status = false; }
		}

		foreach(var entry in crypttab){

			if (redist){
				continue;
			}

			if (exclude_list.contains(entry.name)){ continue; }
			
			//string backup_file = path_combine(backup_path, "%s %s.crypttab".printf(entry.name.replace("/","╱"), entry.device.replace("/","╱")));
			string backup_file = path_combine(files_path, "%s.crypttab".printf(entry.name.replace("/","_")));
			bool ok = file_write(backup_file, entry.get_line());
			chmod(backup_file, "a+rw");
			
			if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file)); }
			else{ status = false; }
		}

		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		return status;
	}

	// restore -------------------------------
	
	public bool restore_mount_entries(){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_MOUNTS));
		log_msg(string.nfill(70,'-'));
		
		if (!dir_exists(files_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		read_selections();
		
		bool status = true, ok;

		this.query_mount_entries();

		var mgr = new MountEntryManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.read_mount_entries_from_folder(files_path);

		ok = this.restore_mount_entries_fstab(mgr.fstab);
		if (!ok){ status = false; }

		if (!redist){

			log_msg(string.nfill(70,'-'));
			
			ok = this.restore_mount_entries_crypttab(mgr.crypttab);
			if (!ok){ status = false; }
		}

		return status;
	}

	private bool restore_mount_entries_fstab(Gee.ArrayList<FsTabEntry> fstab_bkup){

		bool ok = true;
		
		var list = new Gee.ArrayList<FsTabEntry>();

		// add current entries and remove duplicates from bkup ------
		
		foreach(var entry in fstab){
			
			list.add(entry); // keep existing entry

			FsTabEntry? dup = null;
			
			foreach(var item in fstab_bkup){
				if (item.mount_point == entry.mount_point){
					dup = item;
					break;
				}
			}
			
			if (dup != null){
				fstab_bkup.remove(dup);
			}
		}

		// add unique bkup entries -------------

		foreach(var entry in fstab_bkup){

			switch (entry.mount_point){
			case "/":
			case "/home":
			case "/boot":
			case "/boot/efi":
				continue; // it's too risky to migrate these entries
			}
			
			list.add(entry);
		}

		// sort --------------------

		list.sort((a,b)=>{ return strcmp(a.mount_point, b.mount_point); });

		// create missing mount folders -----------------

		foreach(var entry in list){
			
			if (!entry.mount_point.has_prefix("/")){ continue; }
			
			if (!dir_exists(entry.mount_point)){
	
				dir_create(entry.mount_point, true);
			}
		}
		
		// save changes -----------
		
		if (!dry_run){
			
			fstab = list;
			ok = save_fstab_file(fstab);
		}

		// print ---------------------

		log_msg("");
		
		foreach(var entry in list){
			
			entry.print_line();
		}

		return ok;
	}

	private bool restore_mount_entries_crypttab(Gee.ArrayList<CryptTabEntry> crypttab_bkup){

		bool ok = true;
		
		var list = new Gee.ArrayList<CryptTabEntry>();

		// add current entries and remove duplicates from bkup ------
		
		foreach(var entry in crypttab){
			
			list.add(entry); // keep existing entry

			CryptTabEntry? dup = null;
			foreach(var item in crypttab_bkup){
				if (item.name == entry.name){
					dup = item;
					break;
				}
			}
			if (dup != null){
				crypttab_bkup.remove(dup);
			}
		}

		// add unique bkup entries -------------

		foreach(var entry in crypttab_bkup){

			list.add(entry);
		}

		// sort --------------------

		list.sort((a,b)=>{ return strcmp(a.name, b.name); });

		// warn missing key files -----------------

		foreach(var entry in list){
			
			if (!entry.password.has_prefix("/")){ continue; }
			
			if (!file_exists(entry.password)){
	
				log_error("%s: %s: %s".printf("/etc/crypttab", _("Keyfile not found"), entry.password));
			}
		}
		
		// save changes -----------

		if (!dry_run){
			
			crypttab = list;
			ok = save_crypttab_file(crypttab);
		}

		// print ---------------------

		log_msg("");
		
		foreach(var entry in list){
			
			entry.print_line();
		}

		string pkg = "cryptsetup";
		if (!cmd_exists("cryptsetup")){
			log_msg(string.nfill(70,'-'));
			log_msg("%s\n".printf("Installing cryptsetup..."));
			PackageManager.install_package(pkg, pkg, pkg);
		}

		return ok;
	}
}
