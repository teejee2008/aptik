
public class Messages : GLib.Object {
	public const string APT_GET_ERROR = _("Package installation has failed or was aborted by user");

	public const string INTERNET_OFFLINE = _("Internet connection is not active. Check the connection and try again.");
	
	public const string BACKUP_OK = _("Backup completed");
	public const string BACKUP_ERROR = _("Backup completed with errors");
	public const string BACKUP_SAVED = _("Backup saved");
	public const string BACKUP_SAVE_ERROR = _("Failed to save backup");

	public const string UNKNOWN_DISTRO = _("Unknown Linux Distribution & Package Manager");
	public const string UNKNOWN_CODENAME = _("CODENAME is unknown for this Linux distribution");

	public const string MISSING_PACKAGE_MANAGER = _("Package Manager Not Found");

	public const string MISSING_COMMAND = _("Missing command");

	public const string CACHE_NOT_SUPPORTED = _("Cache backup & restore not supported for package manager");
	
	public const string RESTORE_OK = _("Restore completed");
	public const string RESTORE_ERROR = _("Restore completed with errors");

	public const string FILE_EXISTS = _("File exists");
	public const string FILE_MISSING = _("File not found");
	
	public const string FILE_SAVE_OK = _("File saved");
	public const string FILE_SAVE_ERROR = _("Failed to save file");

	public const string FILE_READ_OK = _("File read");
	public const string FILE_READ_ERROR = _("Failed to read file");
	
	public const string FILE_DECRYPT_OK = _("File decrypted");
	public const string FILE_DECRYPT_ERROR = _("Failed to decrypt file");
	
	public const string FILE_DELETE_OK = _("File deleted");
	public const string FILE_DELETE_ERROR = _("Failed to delete file");
	
	public const string DIR_CREATE_OK = _("Directory created");
	public const string DIR_CREATE_ERROR = _("Failed to create directory");

	public const string DIR_EXISTS = _("Directory exists");
	public const string DIR_MISSING = _("Directory missing");

	public const string USER_ADD_OK = _("User added");
	public const string USER_ADD_ERROR = _("Failed to add user");

	public const string GROUP_ADD_OK = _("Group added");
	public const string GROUP_ADD_ERROR = _("Failed to add group");

	public const string GROUP_ADD_USER_OK = _("User added to group");
	public const string GROUP_ADD_USER_ERROR = _("Failed to add user to group");
	
	public const string NO_CHANGES_REQUIRED = _("No changes required");

	public const string PASSWORD_MISSING = _("Password not specified!");
	public const string ENTER_PASSWORD_BACKUP = _("Enter password for encrypting backup");
	public const string ENTER_PASSWORD_RESTORE = _("Enter password for decrypting backup");
	public const string PASSWORD_EMPTY = _("Password cannot be empty!");
	public const string PASSWORD_NOT_MATCHING = _("Passwords do not match!");

	public const string TASK_REPOS = _("Software Repositories");
	public const string TASK_CACHE = _("Downloaded Packages");
	public const string TASK_PACKAGES = _("Installed Software");
	public const string TASK_HOME = _("Home Directory Data");
	public const string TASK_MOUNTS = _("Mount Entries");
	public const string TASK_ICONS = _("Icons");
	public const string TASK_THEMES = _("Themes");
	public const string TASK_FONTS = _("Fonts");
	public const string TASK_USERS = _("User Accounts");
	public const string TASK_GROUPS = _("User Groups");
	public const string TASK_DCONF = _("Dconf Settings");
	public const string TASK_CRON = _("Scheduled Tasks");
}

