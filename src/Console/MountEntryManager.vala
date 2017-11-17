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

public class MountEntryManager : GLib.Object {

	public Gee.ArrayList<FsTabEntry> fstab;
	public Gee.ArrayList<CryptTabEntry> crypttab;

	public bool dry_run = false;

	public MountEntryManager(bool _dry_run){

		dry_run = _dry_run;
		
		fstab = new Gee.ArrayList<FsTabEntry>();
		crypttab = new Gee.ArrayList<CryptTabEntry>();
	}

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
		
		foreach(var entry in list){
			
			txt += "%s\n".printf(entry.get_line());
			
			if (entry.mount_point == "/"){
				found_root = true;
			}
		}

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

		foreach(var entry in list){
			
			txt += "%s\n".printf(entry.get_line());
		}
		
		var t = Time.local (time_t ());

		string file_path = "/etc/crypttab";
		
		string cmd = "mv -vf %s %s.bkup.%s".printf(file_path, file_path, t.format("%Y-%d-%m_%H-%M-%S"));
		Posix.system(cmd);
		
		bool ok = file_write(file_path, txt);

		if (ok){ log_msg("%s: %s".printf(_("Saved"), file_path)); }
		
		return ok;
	}

	// backup and restore ----------------------
	
	public void list_mount_entries(){

		log_msg("/etc/fstab :\n");

		fstab.sort((a,b)=>{ return strcmp(a.mount_point, b.mount_point); });
		
		foreach(var entry in fstab){
			
			entry.print_line();
		}

		log_msg(string.nfill(70,'-'));

		log_msg("/etc/crypttab :\n");

		crypttab.sort((a,b)=>{ return strcmp(a.name, b.name); });

		foreach(var entry in crypttab){
			
			entry.print_line();
		}

		log_msg(string.nfill(70,'-'));
	}

	public bool backup_mount_entries(string basepath){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_MOUNTS));
		log_msg(string.nfill(70,'-'));
		
		string backup_path = path_combine(basepath, "mounts");
		dir_create(backup_path);

		bool status = true;

		foreach(var entry in fstab){
			
			string backup_file = path_combine(backup_path, "%s %s.fstab".printf(entry.device.replace("/","╱"), entry.mount_point.replace("/","╱")));
			bool ok = file_write(backup_file, entry.get_line());

			if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file)); }
			else{ status = false; }
		}

		foreach(var entry in crypttab){
			
			string backup_file = path_combine(backup_path, "%s %s.crypttab".printf(entry.name.replace("/","╱"), entry.device.replace("/","╱")));
			bool ok = file_write(backup_file, entry.get_line());

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

	public bool restore_mount_entries(string basepath){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_MOUNTS));
		log_msg(string.nfill(70,'-'));
		
		string backup_path = path_combine(basepath, "mounts");
		chmod(backup_path, "a+rwx");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		bool status = true, ok;

		query_mount_entries();

		var mgr = new MountEntryManager(dry_run);
		mgr.read_mount_entries_from_folder(backup_path);

		ok = restore_mount_entries_fstab(mgr.fstab);
		if (!ok){ status = false; }

		log_msg(string.nfill(70,'-'));
		
		ok = restore_mount_entries_crypttab(mgr.crypttab);
		if (!ok){ status = false; }
		
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

			if (entry.mount_point == "/boot/efi"){
				continue; // do not add if not already existing
			}

			if (entry.mount_point == "/boot"){
				continue; // do not add if not already existing
			}

			if (entry.mount_point == "/home"){
				continue; // do not add if not already existing
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

		return ok;
	}
}
