#! /usr/bin/env bash

# DESCRIPTION
# Defines software installer functions.

# Mounts a disk image.
# Parameters:
# $1 = The image path.
mount_image() {
  printf "Mounting image...\n"
  hdiutil attach -quiet -nobrowse -noautoopen "$1"
}
export -f mount_image

# Unmounts a disk image.
# Parameters:
# $1 = The mount path.
unmount_image() {
  printf "Unmounting image...\n"
  hdiutil detach -force "$1"
}
export -f unmount_image

# Downloads an installer to local disk.
# Parameters:
# $1 = The URL.
# $2 = The file name.
# $3 = The HTTP header.
download_installer() {
  local url="$1"
  local file_name="$2"
  local http_header="$3"

  printf "%s\n" "Downloading $1..."
  clean_work_path
  mkdir $MAC_OS_WORK_PATH
  curl --header "$http_header" --location --retry 3 --retry-delay 5 --fail --silent --show-error "$url" >> "$MAC_OS_WORK_PATH/$file_name"
}
export -f download_installer

# Downloads an installer to the $HOME/Downloads folder for manual use.
# Parameters:
# $1 = The URL.
# $2 = The file name.
download_only() {
  if [[ -e "$HOME/Downloads/$2" ]]; then
    printf "Downloaded: $2.\n"
  else
    printf "Downloading $1...\n"
    download_installer "$1" "$2"
    mv "$MAC_OS_WORK_PATH/$2" "$HOME/Downloads"
  fi
}
export -f download_only

# Installs a single file.
# Parameters:
# $1 = The URL.
# $2 = The install path.
install_file() {
  local file_url="$1"
  local file_name=$(get_file_name "$1")
  local install_path="$2"

  if [[ ! -e "$install_path" ]]; then
    printf "Installing: $install_path...\n"
    download_installer "$file_url" "$file_name"
    mkdir -p $(dirname "$install_path")
    mv "$MAC_OS_WORK_PATH/$file_name" "$install_path"
    printf "Installed: $file_name.\n"
    verify_path "$install_path"
  fi
}
export -f install_file

# Installs an application.
# Parameters:
# $1 = The application source path.
# $2 = The application name.
install_app() {
  local install_root=$(get_install_root "$2")
  local file_extension=$(get_file_extension "$2")

  printf "Installing: $install_root/$2...\n"

  case $file_extension in
    'app')
      cp -a "$1/$2" "$install_root";;
    'prefPane')
      sudo cp -pR "$1/$2" "$install_root";;
    'qlgenerator')
      sudo cp -pR "$1/$2" "$install_root" && qlmanage -r;;
    *)
      printf "ERROR: Unknown file extension: $file_extension.\n"
  esac
}
export -f install_app

# Installs a package.
# Parameters:
# $1 = The package source path.
# $2 = The application name.
install_pkg() {
  local install_root=$(get_install_root "$2")

  printf "Installing: $install_root/$2...\n"
  local package=$(sudo find "$1" -maxdepth 1 -type f -name "*.pkg" -o -name "*.mpkg")
  sudo installer -pkg "$package" -target /
}
export -f install_pkg

# Installs Java.
# Parameters:
# $1 = The URL.
# $2 = The volume name.
install_java() {
  local url="$1"
  local volume_path="/Volumes/$2"
  local app_name="java"
  local install_path="/usr/bin/$app_name"
  local download_file="download.dmg"

  download_installer "$url" "$download_file" "Cookie: oraclelicense=accept-securebackup-cookie"
  mount_image "$MAC_OS_WORK_PATH/$download_file"
  local package=$(sudo find "$volume_path" -maxdepth 1 -type f -name "*.pkg")
  sudo installer -pkg "$package" -target /
  unmount_image "$volume_path"
  printf "Installed: $app_name.\n"
}
export -f install_java

# Installs an application via a DMG file.
# Parameters:
# $1 = The URL.
# $2 = The mount path.
# $3 = The application name.
install_dmg_app() {
  local url="$1"
  local mount_point="/Volumes/$2"
  local app_name="$3"
  local install_path=$(get_install_path "$app_name")
  local download_file="download.dmg"

  if [[ ! -e "$install_path" ]]; then
    download_installer "$url" "$download_file"
    mount_image "$MAC_OS_WORK_PATH/$download_file"
    install_app "$mount_point" "$app_name"
    unmount_image "$mount_point"
    verify_application "$app_name"
  fi
}
export -f install_dmg_app

# Runs an application installer enclosed in a DMG file.
# Parameters:
# $1 = The URL.
# $2 = The mount path.
# $3 = The installer name.
# $4 = The application name.
install_dmg_installer() {
  local url="$1"
  local mount_point="/Volumes/$2"
  local installer_name="$3"
  local app_name="$4"
  local install_path=$(get_install_path "$app_name")
  local download_file="download.dmg"

  if [[ ! -e "$install_path" ]]; then
    download_installer "$url" "$download_file"
    mount_image "$MAC_OS_WORK_PATH/$download_file"
    
    printf "Running installer: $installer_name...\n"
	
	#Block for processing of installer
	open -W "$mount_point/$installer_name"
	unmount_image "$mount_point"
    printf "Installed: $app_name.\n"
    verify_application "$app_name"
	
	#Open in background for uninterrupted mode
	#open -g $mount_point/$installer_name	
  fi
}
export -f install_dmg_installer

# Runs an application installer enclosed in a zip file.
# Parameters:
# $1 = The URL.
# $2 = The installer name.
# $3 = The application name.
install_zip_installer() {
  local url="$1"
  local installer_name="$2"
  local app_name="$3"
  local install_path=$(get_install_path "$app_name")
  local download_file="download.dmg"

  if [[ ! -e "$install_path" ]]; then
    download_installer "$url" "$download_file"
	
    (
      printf "Preparing...\n"
      cd "$MAC_OS_WORK_PATH"
      unzip -q "$download_file"
    )
		
    printf "Running installer: $installer_name...\n"
	#Block for processing of installer
	open -W "$installer_name"
    printf "Installed: $app_name.\n"
    verify_application "$app_name"
	
	#Open in background for uninterrupted mode
	#open -g "$installer_name"
  fi
}
export -f install_zip_installer

# Runs a cmd on the output of a zip file.
# Parameters:
# $1 = The URL.
# $2 = The installer cmd.
# $3 = The installation check path.
install_zip_install_cmd() {
  local url="$1"
  local installer_cmd="$2"
  local install_path="$3"
  local download_file="download.zip"

  if [[ ! -e "$install_path" ]]; then
    download_installer "$url" "$download_file"
	
    (
      printf "Preparing...\n"
      cd "$MAC_OS_WORK_PATH"
      unzip -q "$download_file"
    )
		
    printf "Running installer: $installer_cmd...\n"

	sudo $MAC_OS_WORK_PATH/$installer_cmd
    printf "Installed: $app_name.\n"
    verify_application "$app_name"
  fi
}
export -f install_zip_install_cmd

# Installs a package from a DMG file, with an installation check.
# Parameters:
# $1 = The URL.
# $2 = The mount path.
# $3 = The intaller name.
# $4 = Installation check path
install_dmg_pkg() {
  local url="$1"
  local mount_point="/Volumes/$2"
  local app_name="$3"
  local install_path="$4"
  local download_file="download.dmg"

  if [[ ! -e "$install_path" ]]; then
    download_installer "$url" "$download_file"
    mount_image "$MAC_OS_WORK_PATH/$download_file"
    install_pkg "$mount_point" "$app_name"
    unmount_image "$mount_point"
    printf "Installed: $app_name.\n"
    verify_application "$app_name"
  fi
}
export -f install_dmg_pkg


# Installs a package downloaded straight from the internet..
# Parameters:
# $1 = The URL.
# $2 = The application name.
install_raw_pkg() {
  local url="$1"
  local app_name="$2"
  local install_path=$(get_install_path "$app_name") 
  local download_file="download.pkg"

  if [[ ! -e "$install_path" ]]; then
    download_installer "$url" "$download_file"
    install_pkg "$MAC_OS_WORK_PATH/$download_file" "$app_name"
    printf "Installed: $app_name.\n"
    verify_application "$app_name"
  fi
}
export -f install_raw_pkg

# Installs an application via a zip file.
# Parameters:
# $1 = The URL.
# $2 = The application name.
install_zip_app() {
  local url="$1"
  local app_name="$2"
  local install_path=$(get_install_path "$app_name")
  local download_file="download.zip"

  if [[ ! -e "$install_path" ]]; then
    download_installer "$url" "$download_file"

    (
      printf "Preparing...\n"
      cd "$MAC_OS_WORK_PATH"
      unzip -q "$download_file"
      find . -type d -name "$app_name" -print -exec cp -pR {} . > /dev/null 2>&1 \;
    )

    install_app "$MAC_OS_WORK_PATH" "$app_name"
    printf "Installed: $app_name.\n"
    verify_application "$app_name"
  fi
}
export -f install_zip_app

# Installs an application via a tar file.
# Parameters:
# $1 = The URL.
# $2 = The application name.
# $3 = The decompress options.
install_tar_app() {
  local url="$1"
  local app_name="$2"
  local options="$3"
  local install_path=$(get_install_path "$app_name")
  local download_file="download.tar"

  if [[ ! -e "$install_path" ]]; then
    download_installer "$url" "$download_file"

    (
      printf "Preparing...\n"
      cd "$MAC_OS_WORK_PATH"
      tar "$options" "$download_file"
    )

    install_app "$MAC_OS_WORK_PATH" "$app_name"
    printf "Installed: $app_name.\n"
    verify_application "$app_name"
  fi
}
export -f install_tar_app

# Installs a package via a zip file.
# Parameters:
# $1 = The URL.
# $2 = The application name.
install_zip_pkg() {
  local url="$1"
  local app_name="$2"
  local install_path=$(get_install_path "$app_name")
  local download_file="download.zip"

  if [[ ! -e "$install_path" ]]; then
    download_installer "$url" "$download_file"

    (
      printf "Preparing...\n"
      cd "$MAC_OS_WORK_PATH"
      unzip -q "$download_file"
    )

    install_pkg "$MAC_OS_WORK_PATH" "$app_name"
    printf "Installed: $app_name.\n"
    verify_application "$app_name"
  fi
}
export -f install_zip_pkg

# Installs application code from a Git repository.
# Parameters:
# $1 = Repository URL.
# $2 = Install path.
# $3 = Git clone options (if any).
install_git_app() {
  local repository_url="$1"
  local app_name=$(get_file_name "$2")
  local install_path="$2"
  local options="--quiet"

  if [[ -n "$3" ]]; then
    local options="$options $3"
  fi

  if [[ ! -e "$install_path" ]]; then
    printf "Installing: $install_path/$app_name...\n"
    git clone $options "$repository_url" "$install_path"
    printf "Installed: $app_name.\n"
    verify_path "$install_path"
  fi
}
export -f install_git_app

# Installs settings from a Git repository.
# Parameters:
# $1 = The repository URL.
# $2 = The repository version.
# $3 = The project directory.
# $4 = The script to run (including any arguments).
install_git_project() {
  local repo_url="$1"
  local repo_version="$2"
  local project_dir="$3"
  local script="$4"

  git clone "$repo_url"
  (
    cd "$project_dir"
    git checkout "$repo_version"
    eval "$script"
  )
  rm -rf "$project_dir"
}
export -f install_git_project
