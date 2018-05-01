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
	
	//public Gee.HashMap<string,Font> fonts = new Gee.HashMap<string, Font>();

	public Gee.HashMap<string,Font> fonts = new Gee.HashMap<string,Font>();
	
	public FontManager(LinuxDistro _distro, User _current_user, string _basepath, bool _dry_run, bool _redist, bool _apply_selections){

		base(_distro, _current_user, _basepath, _dry_run, _redist, _apply_selections, "fonts");

		query();
	}
	
	public void list_fonts2(){

		string cmd = "fc-list : file family style";
		string std_out, std_err;
		exec_sync(cmd, out std_out, out std_err);
		
		foreach (string line in std_out.split("\n")){
			
			var match = regex_match("""(.*):(.*):style=(.*)""", line);
			
			if (match != null){

				string file = match.fetch(1);
				string family = match.fetch(2);
				string style = match.fetch(3);

				if (!fonts.has_key(family)){
					//fonts[family] = new Font(family);
				}
				
				var font = fonts[family];
				font.add_style(style);
			}
		}

		foreach(var font in fonts_sorted){
			//log_msg("%s -- %s".printf(font.family, font.style));
			//log_msg("%s".printf(font.family));
		}
	}

	public void query(){

		var list = dir_list_files_recursive("/usr/share/fonts/", true);

		foreach(var file in list){

			if (!is_font_file(file)){ continue; }
			
			fonts[file] = new Font(file, "", "");
		}
	}

	public void list_fonts(){

		foreach(var font_file in fonts_sorted){
			
			log_msg("%s".printf(font_file));
		}
	}

	public Gee.ArrayList<string> fonts_sorted {
		owned get{
			return get_sorted_array(fonts);
		}
	}

	// list --------------------------------

	public void dump_info(){

		string txt = "";
		
		foreach(var font_file in fonts_sorted){

			if (!is_font_file(font_file)){ continue; }

			txt += "NAME='%s'".printf(font_file.replace("/usr/share/fonts/",""));

			bool is_dist = false;
			foreach(string dist_file in App.dist_files_fonts){
				if (font_file == dist_file){
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
		
		foreach(var font_file_bkup in list_bkup){

			txt += "NAME='%s'".printf(font_file_bkup.replace(files_path + "/",""));

			bool is_installed = false;
			foreach(string font_file in list_sys){
				if (font_file.replace("/usr/share/fonts/","") == font_file_bkup.replace(files_path + "/","")){
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

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_FONTS));
		log_msg(string.nfill(70,'-'));

		// begin ----------------------------
		
		string system_path = "/usr/share/fonts";
		
		init_backup_path();

		read_selections();

		// exclude list for rsync ---------------------------------------

		save_exclude_list();

		// system fonts --------------------------

		backup_fonts_from_path(system_path);

		// users' fonts -------------------------
		
		/*var mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
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
		}*/

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

		cmd += " --prune-empty-dirs";
		
		cmd += " --exclude=cmap/ --exclude=type1/ --exclude=X11/";

		string list_file = path_combine(backup_path, "exclude.list");
		
		if (file_exists(list_file)){
			cmd += " --exclude-from='%s'".printf(escape_single_quote(list_file));
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

	private string save_exclude_list(){
		
		string list_file = path_combine(backup_path, "exclude.list");

		string txt = "";
		
		if (App.dist_files_fonts.size > 0){

			foreach(string path in App.dist_files_fonts){
				
				if (path.has_prefix("/usr/share/fonts/") && !dir_exists(path)){
					
					txt += path["/usr/share/fonts/".length: path.length] + "\n";
				}
			}
		}

		foreach(string path in exclude_list){
			
			txt += path + "\n";
		}
		
		file_write(list_file, txt);
		chmod(list_file, "a+rw");
		
		log_msg("%s: %s".printf(_("saved"), list_file.replace(basepath, "$basepath")));

		if (file_exists(list_file)){
			
			foreach(string path in file_read(list_file).split("\n")){
				
				if (is_font_file(path)){
					
					log_msg("%s: %s".printf(_("exclude"), path));
				}
			}

			log_msg("");
		}

		return list_file;
	}

	private bool is_font_file(string path){
		
		return path.has_suffix(".ttf") || path.has_suffix(".ttc")
			|| path.has_suffix(".otf")
			|| path.has_suffix(".pfa") || path.has_suffix(".afm")  // linux   - font file and metric file
			|| path.has_suffix(".pfb") || path.has_suffix(".pfm"); // windows - font file and metric file
	}
	
	// restore ---------------------------------------
	
	public bool restore_fonts(){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_FONTS));
		log_msg(string.nfill(70,'-'));
		
		string system_path = "/usr/share/fonts";
		
		if (!dir_exists(backup_path)){
			log_error("%s: %s".printf(_("Directory not found"), backup_path));
			return false;
		}

		string list_file = save_exclude_list();

		string cmd = "rsync -avh";

		cmd += " --ignore-existing";

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=cmap/ --exclude=type1/ --exclude=X11/";

		if (file_exists(list_file)){
			cmd += " --exclude-from='%s'".printf(escape_single_quote(list_file));
		}
		
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
	
	public static Gee.ArrayList<string> get_sorted_array(Gee.HashMap<string,Font> dict){

		var list = new Gee.ArrayList<string>();
		
		foreach(var item in dict.values) {
			list.add(item.file);
		}

		list.sort((a, b) => {
			return strcmp(a.down(), b.down());
		});

		return list;
	}

}

public class Font : GLib.Object {

	public string file = "";
	public string family = "";
	public string style = "";

	public Font(string _file, string _family, string _style){
		file = _file;
		family = _family;
		style = _style;
	}

	public void add_style(string _style){
		if (style.length > 0){ style += ","; }
		style += _style;
	}
}
