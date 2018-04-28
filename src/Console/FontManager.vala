/*
 * FontManager.vala
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

public class FontManager : BackupManager {
	
	public Gee.HashMap<string,Font> fonts = new Gee.HashMap<string, Font>();
	
	public FontManager(LinuxDistro _distro, User _current_user, string _basepath, bool _dry_run, bool _redist, bool _apply_selections){

		base(_distro, _current_user, _basepath, _dry_run, _redist, _apply_selections, "fonts");
	}
	
	public void list_fonts(){

		string cmd = "fc-list : family style";
		string std_out, std_err;
		exec_sync(cmd, out std_out, out std_err);
		
		foreach (string line in std_out.split("\n")){
			
			var match = regex_match("""(.*):style=(.*)""", line);
			
			if (match != null){
				
				string family = match.fetch(1);
				string style = match.fetch(2);

				if (!fonts.has_key(family)){
					fonts[family] = new Font(family);
				}
				
				var font = fonts[family];
				font.add_style(style);
			}
		}

		foreach(var font in fonts_sorted){
			log_msg("%s -- %s".printf(font.family, font.style));
			//log_msg("%s".printf(font.family));
		}
	}

	public Gee.ArrayList<Font> fonts_sorted {
		owned get{
			return get_sorted_array(fonts);
		}
	}

	// list --------------------------------

	public void dump_info(){

		var list = dir_list_files_recursive("/usr/share/fonts", true, null);

		list.sort();
		
		string txt = "";
		
		foreach(var font_file in list){

			if (!font_file.has_suffix(".ttf") && !font_file.has_suffix(".otf")){ continue; }

			txt += "NAME='%s'".printf(font_file);

			bool is_dist = false;
			foreach(string file_path in App.dist_files){
				if (file_path.has_prefix("/usr/share/fonts/") && (font_file == file_path)){
					is_dist = true;
					break;
				}
			}
			
			txt += ",DIST='%s'".printf(is_dist ? "1" : "0");
			
			txt += ",ACT='%s'".printf(is_dist ? "0" : "1");
			
			txt += ",SENS='%s'".printf("1"); // always sensitive
			
			txt += "\n";
		}
		
		log_msg(txt);
	}

	public void dump_info_backup(){

		init_backup_path(false);
		
		if (!dir_exists(files_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, files_path);
			log_error(msg);
			return;
		}
		
		var list_sys = dir_list_files_recursive("/usr/share/fonts", true, null);
		list_sys.sort();

		var list_bkup = dir_list_files_recursive(files_path, true, null);
		list_bkup.sort();
		
		string txt = "";
		
		foreach(var font_file in list_bkup){

			txt += "NAME='%s'".printf(font_file);

			bool is_installed = false;
			foreach(string file_path in list_sys){
				if (file_path.has_prefix("/usr/share/fonts/") && (font_file == file_path)){
					is_installed = true;
					break;
				}
			}
			
			txt += ",INST='%s'".printf(is_installed ? "1" : "0");

			txt += ",ACT='%s'".printf(is_installed ? "0" : "1");
			
			txt += ",SENS='%s'".printf(is_installed ? "0" : "1");
			
			txt += "\n";
		}
		
		log_msg(txt);
	}

	// save -------------------------------------------

	public bool backup_fonts(){

		init_backup_path(false);

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_FONTS));
		log_msg(string.nfill(70,'-'));

		// begin ----------------------------
		
		string system_path = "/usr/share/fonts";
		
		init_backup_path(false);
		
		init_files_path(false);

		read_selections();

		// exclude list for rsync ---------------------------------------

		string list_file = path_combine(backup_path, "exclude.list");
		
		if (App.dist_files.size > 0){

			string txt = "";
			
			foreach(string path in App.dist_files){
				
				if (path.has_prefix("/usr/share/fonts/")){
					
					txt += path["/usr/share/fonts/".length: path.length] + "\n";
				}
			}

			foreach(string path in exclude_list){
				
				if (path.has_prefix("/usr/share/fonts/")){
					
					txt += path["/usr/share/fonts/".length: path.length] + "\n";
				}
			}
			
			file_write(list_file, txt);
			log_msg("%s: %s".printf(_("saved"), list_file.replace(basepath, "$basepath")));
		}

		// print items ------------------------
		
		if (file_exists(list_file)){
			
			foreach(string path in file_read(list_file).split("\n")){
				
				if (path.has_suffix(".ttf") || path.has_suffix(".otf")){
					
					log_msg("%s: %s".printf(_("exclude"), path));
				}
			}

			log_msg("");
		}

		// system fonts --------------------------

		backup_fonts_from_path(system_path);

		// users' fonts -------------------------
		
		var mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_users(false);
		
		foreach(var user in mgr.users.values){

			if (user.is_system) { continue; }
			
			string path = "%s/.fonts".printf(user.home_path);
			var list = dir_list_names(path, true);
			if (list.size > 0){
				log_msg(string.nfill(70,'-'));
				backup_fonts_from_path(path);
			}
			
			path = "%s/.local/share/fonts".printf(user.home_path);
			list = dir_list_names(path, true);
			if (list.size > 0){
				log_msg(string.nfill(70,'-'));
				backup_fonts_from_path(path);
			}
		}

		update_permissions_for_backup_files();

		log_msg(Messages.BACKUP_OK);

		return true;
	}
	
	public bool backup_fonts_from_path(string system_path){

		if (!dir_exists(system_path)){ return false; }

		log_msg("%s: %s".printf(_("Path"), system_path));
		log_msg("");
		
		string cmd = "rsync -avh";
		
		cmd += " -L"; // dereference symlinks to font files

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=cmap/ --exclude=type1/ --exclude=X11/";

		string exclude_list = path_combine(backup_path, "exclude.list");
		
		if (file_exists(exclude_list)){
			cmd += " --exclude-from='%s'".printf(escape_single_quote(exclude_list));
		}

		cmd += " '%s/'".printf(escape_single_quote(system_path));
		
		cmd += " '%s/files/'".printf(escape_single_quote(backup_path));

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug(cmd);
			status = Posix.system(cmd);
		}

		log_msg("");

		return (status == 0);
	}

	// restore ---------------------------------------
	
	public bool restore_fonts(){

		init_backup_path(false);

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_FONTS));
		log_msg(string.nfill(70,'-'));
		
		string system_path = "/usr/share/fonts";
		
		if (!dir_exists(backup_path)){
			log_error("%s: %s".printf(_("Directory not found"), backup_path));
			return false;
		}

		string cmd = "rsync -avh";

		cmd += " --ignore-existing";

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=cmap/ --exclude=type1/ --exclude=X11/";
		cmd += " '%s/files/'".printf(escape_single_quote(backup_path));
		cmd += " '%s/'".printf(escape_single_quote(system_path));

		int status = 0;
	
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug(cmd);
			status = Posix.system(cmd);
		}
		
		log_msg(string.nfill(70,'-'));

		update_permissions_for_restored_files(system_path);

		update_font_cache();

		log_msg(Messages.RESTORE_OK);

		return (status == 0);
	}

	private bool update_font_cache(){

		log_msg(_("Updating font cache:"));
		log_msg("");
		
		string cmd = "fc-cache";
		if (!cmd_exists(cmd)){
			log_error("%s: %s".printf(Messages.MISSING_COMMAND, cmd));
			return false;
		}

		cmd = "fc-cache -fv";
		log_debug(cmd);

		int status = 0;
	
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug(cmd);
			status = Posix.system(cmd);
		}
	
		log_msg(string.nfill(70,'-'));

		return (status == 0);
	}

	// static ----------------------

	public static Gee.ArrayList<Font> get_sorted_array(Gee.HashMap<string,Font> dict){

		var list = new Gee.ArrayList<Font>();
		
		foreach(var pkg in dict.values) {
			list.add(pkg);
		}

		list.sort((a, b) => {
			return strcmp(a.family.down(), b.family.down());
		});

		return list;
	}

}

public class Font : GLib.Object {
	
	public string family = "";
	public string style = "";

	public Font(string _family){
		family = _family;
	}

	public void add_style(string _style){
		if (style.length > 0){ style += ","; }
		style += _style;
	}
}
