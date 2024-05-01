#!/bin/bash
#
#  _____
# |~>   |     _
# |_____|   ('v') 
# /:::::\  /{w w}\ 
#
#
# title: initial-server-setup.sh
# description: server setup script
# autor: Florian Orzol
# date: 01.05.2024
# version: 0.8.1 
# usage: This script is used for my basic server settings
# notes: This script is for beeing executed on first start of the container. With these settings, I am able to script on my main computer and execute the scripts on the server. 



#    <')
# \_;( )
# =============================== #
# >> ENTER YOUR VARIABLES HERE << #
# =============================== #

INSTALL_PACKAGES=(vim rsync git curl wget fzf btop sudo fish sshfs sshpass ranger tmux)
TIMEZONE="Europe/Berlin"
LOCALE="de_DE.UTF-8"

FOLDER_NOTES="_notes"
FOLDER_SYSTEM="_system"

FOLDER_MOUNT_SERVER_MANAGEMENT="mount-server-management"
FOLDER_SYSTEM_INFORMATION="system-information"

PATH_SM="/root/server-management"
PATH_SM_NOTES="$PATH_SM/$FOLDER_NOTES"
PATH_SM_SYSTEM="$PATH_SM/$FOLDER_SYSTEM"
PATH_SM_MOUNT_SERVER_MANAGEMENT="$PATH_SM/$FOLDER_MOUNT_SERVER_MANAGEMENT"
PATH_SM_SYSTEM_INFORMATION="$PATH_SM/$FOLDER_SYSTEM_INFORMATION"


PATH_FS="/root/fileshare"
PATH_FS_SM="/root/fileshare/server-management"

FILE_VARIABLES="$PATH_SM_SYSTEM/variables"

FOLDER_SERVER_MANAGEMENT="server-management"
FOLDER_FILESHARE="fileshare"
FOLDER_LOGS="logs"
FOLDER_BACKUP="backup"
FOLDER_MONITORING="monitoring"
FOLDER_SERVICES="services"

FOLDER_SM_MOUNT="sm-mount"
FOLDER_SERVER_INFORMATION="server-information"



# ------------------------------ #
# >> SYSTEM VARIABLES

PATH_ROOT_FS="/root/$FOLDER_FILESHARE"
PATH_ROOT_FS_SM="/root/$FOLDER_FILESHARE/$FOLDER_SERVER_MANAGEMENT"

PATH_ROOT_SM="/root/$FOLDER_SERVER_MANAGEMENT"
PATH_ROOT_SM_LOGS="$PATH_ROOT_SM/$FOLDER_LOGS"
PATH_ROOT_SM_BACKUP="$PATH_ROOT_SM/$FOLDER_BACKUP"
PATH_ROOT_SM_MONITORING="$PATH_ROOT_SM/$FOLDER_MONITORING"
PATH_ROOT_SM_SERVICES="$PATH_ROOT_SM/$FOLDER_SERVICES"
PATH_ROOT_SM_INFORMATION="$PATH_ROOT_SM/information"
USER_START_CMDS_ON_HOST=""




function main_process {
    initial_conditions
    update_system
    install_packages
    set_general_settings
    create_local_server_management_paths
    enter_variables
    create_systemd_mount_server_management
    config_fileshare_server_management
    set_get_host_information
    set_system_cmds_commands
    create_file_start_on_host
    copy_server_management_to_fileshare_sm_folder
    fish
}


function initial_conditions {
    sector "CHECK INITIAL CONDITIONS"
    subsector "Check if script is executed as root"
    if [[ $EUID -ne 0 ]]; then
        echo -e "\n\e[91mThis script must be run as root\e[0m"
        exit 1
    fi

    subsector "Check if /root/server-management exists"
    if [[ -d $PATH_SM ]]; then
        information "$PATH_SM already exists, would you backup the existing folder and clean the system?"
        question_yn "Would you backup the existing folder and clean the system?" "Y"
        if [[ $? -eq 1 ]]; then
            information "Backup $PATH_SM ..."
            cmd "mv $PATH_SM ${PATH_SM}_bak"
        fi
    fi
} 


function update_system {
    sector "UPDATE SYSTEM"
    subsector "Update system"
    cmd "apt update"
    subsector "Upgrade system"
    cmd "apt dist-upgrade -y"
    subsector "Autoremove"
    cmd "apt autoremove -y"
}


function install_packages {
    sector "INSTALL PACKAGES"
    subsector "Install vim"
    cmd "apt install -y vim # install vim seperately - vim.tiny is installed by default"
    for package in "${INSTALL_PACKAGES[@]}"
    do
        subsector "Install $package"
        # check if package is already installed
        if [[ $(dpkg -l | grep $package) != "" ]]; then
            information "$package is already installed, skipping ..."
            continue
        fi
        cmd "apt install -y $package"
    done
}


function set_general_settings {
    sector "SET GENERAL SETTINGS"
    subsector "Set timezone"
    cmd "timedatectl set-timezone $TIMEZONE"
    subsector "Set locale"
    cmd "locale-gen $LOCALE"
    information "If you want to have the ability to run scripts and commands directly from your computer, you will need root-permissions via ssh connection. Disabling ssh-root-logins means connecting with user rights via ssh and requiring the user password for every command sent from the client. Enabling this option increases the security risk. If you are unsure, it is recommended not to enable this option."
    question_yn "Set ssh root login to yes?" "N"
    if [[ $? -eq 1 ]]; then
        sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
        USER_START_CMDS_ON_HOST="root"
    fi
    subsector "Set fuser mount allow other"
    cmd "echo \"user_allow_other\" >> /etc/fuse.conf"
    subsector "Set fish as default shell in debian"
    cmd "chsh -s /usr/bin/fish root"
}


function create_local_server_management_paths {
    sector "CREATE LOCAL SERVER-MANAGEMENT PATHS"
    ARRAY_SM_PATHS=("$PATH_SM" "$PATH_SM_NOTES" "$PATH_SM_SYSTEM" "$PATH_SM/_backups"
        "$PATH_SM_MOUNT_SERVER_MANAGEMENT" "$PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files" "$PATH_SM_MOUNT_SERVER_MANAGEMENT/logs" "$PATH_SM_MOUNT_SERVER_MANAGEMENT/monitoring" "$PATH_SM_MOUNT_SERVER_MANAGEMENT/archive" "$PATH_SM_MOUNT_SERVER_MANAGEMENT/_notes"
        "$PATH_SM/system-information"  "$PATH_SM/system-information/script-files" "$PATH_SM/system-information/logs" "$PATH_SM/system-information/monitoring" "$PATH_SM/system-information/archive" "$PATH_SM/system-information/_notes")
    
    for path in "${ARRAY_SM_PATHS[@]}"
    do
        subsector "Create $path"
        # check if path exists
        if [[ -d $path ]]; then
            information "$path already exists, skipping ..."
            continue
        fi
        cmd "mkdir $path"
    done
}


function enter_variables {
    sector "ENTER VARIABLES"


    function use_existing_variables {
        if [[ -f $FILE_VARIABLES ]]; then
        question_yn "$FILE_VARIABLES exists, use these variables?" "N"
            if [[ $? -eq 1 ]] ; then
                information "Take variables from $FILE_VARIABLES"
                sleep 2
                cmd "source $FILE_VARIABLES"
                return 1
            else
                information "Delete $FILE_VARIABLES ..."
                cmd "rm $FILE_VARIABLES"
            fi
        fi
        return 0
    }


    function create_user {
        subsector "Create user"
        information "Enter username ..."
        while true; do
            read -p "$ " USERNAME
            question_yn "Is $USERNAME correct?" "Y"
            if [[ $? -eq 1 ]]; then
                break
            fi
        done
        # check if USERNAME already exists
        if id "$USERNAME" >/dev/null 2>&1; then
            information "$USERNAME already exists, no need to create again ..."
        else
            information "Creating $USERNAME ..."
            adduser $USERNAME --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
        fi
        information "Enter user password for $USERNAME ..." 
        while true; do
            echo -en "$ "
            read -s PASSWORD
            information "Enter user password again for $USERNAME ..."
            echo -en "$ "
            read -s PASSWORD_AGAIN
            if [[ $PASSWORD != $PASSWORD_AGAIN ]]; then
                information "Passwords do not match, try again ..."
                continue
            else
                #cmd "echo $USERNAME:$PASSWORD | chpasswd"
                echo $USERNAME:$PASSWORD | chpasswd
                break
            fi
        done
        information "Adding $USERNAME to sudo group ..."
        cmd "usermod -aG sudo $USERNAME"
        if [[ $USER_START_CMDS_ON_HOST == "" ]]; then
            USER_START_CMDS_ON_HOST=$USERNAME
        fi
    }


    function set_fileshare_variables {
        subsector "Set fileshare variables"
        while true; do
            information "Enter fileshare host (or ip) ..."
            while true; do
                read -p "$ " FILESHARE_HOST
                information "Checking if $FILESHARE_HOST is reachable ..."
                if [[ $(ping -c 1 $FILESHARE_HOST) == "" ]]; then
                    information "$FILESHARE_HOST is not reachable ..."
                else
                    information "$FILESHARE_HOST is reachable ..."
                fi
                question_yn "Is $FILESHARE_HOST correct?" "Y"
                if [[ $? -eq 1 ]]; then
                    break
                fi
            done

            information "Enter fileshare username ..."
            while true; do
                read -p "$ " FILESHARE_USERNAME
                question_yn "Is $FILESHARE_USERNAME correct?" "Y"
                if [[ $? -eq 1 ]]; then
                    break
                fi
            done

#            information "Enter fileshare password ..."
#            while true; do
#                echo -en "$ "
#                read -s FILESHARE_PASSWORD
#                information "Enter fileshare password again ..."
#                echo -en "$ "
#                read -s FILESHARE_PASSWORD_AGAIN
#                if [[ $FILESHARE_PASSWORD != $FILESHARE_PASSWORD_AGAIN ]]; then
#                    information "Passwords do not match, try again ..."
#                    continue
#                else
#                    break
#                fi
#            done

            cmd "ssh-keygen"

            cmd "ssh-copy-id $FILESHARE_USERNAME@$FILESHARE_HOST"

            information "Enter fileshare host Server-manager path ..."
            while true; do
                read -p "$ " FILESHARE_HOST_PATH
                question_yn "Is $FILESHARE_HOST_PATH correct?" "Y"
                if [[ $? -eq 1 ]]; then
                    break
                fi
            done
            
            #output=$(sshpass -p $FILESHARE_PASSWORD ssh -o StrictHostKeyChecking=no $FILESHARE_USERNAME@$FILESHARE_HOST ls $FILESHARE_HOST_PATH 2>&1)
            output=$(ssh $FILESHARE_USERNAME@$FILESHARE_HOST ls $FILESHARE_HOST_PATH 2>&1)
            if  [[ $output == *"Permission denied"* ]]; then
                information "$FILESHARE_USERNAME, $FILESHARE_PASSWORD is not correct ..."
            elif [[ $output == *"No such file or directory"* ]]; then
                information "$FILESHARE_HOST_PATH is not correct ..."
            elif [[ $output == *"ls: cannot access"* ]]; then
                information "$FILESHARE_HOST_PATH is not correct ..."
            elif [[ $output == "" ]]; then
                information "$FILESHARE_HOST is not reachable ..."
            else
                information "host[$FILESHARE_HOST], user[$FILESHARE_USERNAME], password[***] and path[$FILESHARE_HOST_PATH] seems to be correct ..."
                output="ok"
            fi
            if [[ $output == "ok" ]]; then
                question_yn "Are the fileshare entries correct?" "Y"
                if [[ $? -eq 1 ]]; then 
                    break
                else
                    information "Removing known_hosts entry ..."
                    cmd "ssh-keygen -R $FILESHARE_HOST"
                    information "Trying again ..."
                fi
            else
                question_yn "Are the fileshare entries correct?" "N"
                if [[ $? -eq 1 ]] ; then 
                    break;
                else
                    information "Removing known_hosts entry ..."
                    cmd "ssh-keygen -R $FILESHARE_HOST"
                    information "Trying again ..."
                fi
            fi
        done
    }


    function set_fileshare_folder_name_for_server_management {
        subsector "Enter fileshare folder name"
        question_yn "Would you take the hostname as (lowercase-) fileshare folder?" "Y"
        if [[ $? -eq 1 ]]; then
            # set container name to hostname
            information "Setting fileshare folder name to (lowercase-) hostname ..."
            FOLDER_SERVER_FOLDERNAME=$(hostname | tr '[:upper:]' '[:lower:]')
        else
            information "Enter container name ..."
            while true; do
                read -p "$ " FOLDER_SERVER_FOLDERNAME
                question_yn "Is $FOLDER_SERVER_FOLDERNAME correct?" "Y"
                if [[ $? -eq 1 ]]; then
                    break
                fi
            done
        fi
        PATH_FS_SM_FOLDERNAME="$PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"
    }


    function save_variables_to_host_data {
        information "Saving variables to $FILE_VARIABLES ..."
        WRITE_FILE_HOST_DATA
        information "Setting rights for $FILE_VARIABLES ..."
        cmd "chmod 600 $FILE_VARIABLES"
        information "Saving support functions to $PATH_SM/_system/support-functions ..."
        WRITE_FILE_SUPPORT_FUNCTIONS
    }


    use_existing_variables
    if [[ $? -eq 1 ]]; then
        return 0
    fi

    create_user
    set_fileshare_variables
    set_fileshare_folder_name_for_server_management
    save_variables_to_host_data
    information "Set fish as default shell for $USERNAME ..."
    cmd "chsh -s /usr/bin/fish $USERNAME"
}


function create_start_on_host_file {
    WRITE_FILE_START_ON_HOST
    information "Setting rights for soh-$FOLDER_SERVER_FOLDERNAME ..."
    cmd "chmod +x $PATH_SM_SYSTEM/soh-$FOLDER_SERVER_FOLDERNAME"
}


function create_systemd_mount_server_management {

    sector "CONFIGURE SSHFS FILESHARE"
    

    function generate_ssh_keygen {
        subsector "Generate ssh-keygen"
        if [[ -f /root/.ssh/id_rsa ]]; then
            information "ssh-keygen already exists, no need to create again ..."
        else
            information "Creating ssh-keygen ..."
            cmd "ssh-keygen -t rsa -N \"\" -f /root/.ssh/id_rsa"
        fi
    }


    function copy_fileshare_host_public_key {
        subsector "Copying fileshare host public key"
        cmd "sshpass -p $FILESHARE_PASSWORD ssh-copy-id $FILESHARE_USERNAME@$FILESHARE_HOST"
    }


    function create_sshfs_mountpoint {
        subsector "Create sshfs mountpoint"
        if [[ -d $PATH_FS_SM ]]; then
            information "sshfs mountpoint already exists, no need to create again ..."
        else
            information "Creating sshfs mountpoint $PATH_FS_SM ..."
            cmd "mkdir -p $PATH_FS_SM"
        fi
    }


    function create_mount_sm_root_service {
        subsector "Create systemd mount-server-management.service"
        if [[ -f $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-server-management.service ]]; then
            information "systemd service mount-server-management.service already exists, no need to create again ..."
        else
            information "Creating systemd service mount-server-management.service ..."
            WRITE_FILE_SYSTEMD_MOUNT_SERVER_MANAGEMENT_ROOT
        fi
    }


    function link_mount_sm_root_service {
        subsector "Create link to /etc/systemd/system/"
        if [[ -L /etc/systemd/system/mount-server-management.service && -e /etc/systemd/system/mount-server-management.service ]]; then
            information "link already exists, no need to create again ..."
        else
            information "Creating link ..."
            cmd "ln -s $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-server-management.service /etc/systemd/system/"
        fi
    }


    function enable_and_start_mount_sm_root_service {
        subsector "Enable and start systemd mount-server-management.service"
        cmd "systemctl enable --now mount-server-management.service"
    }


    function check_mount_sm_root_service {
        subsector "Check if $PATH_FS_SM is mounted"
        for i in {1..5}; do
            if [[ $(mount | grep $PATH_FS_SM) != "" ]]; then
                information "$PATH_FS_SM is mounted ..."
                break
            else
                information "Waiting for $PATH_FS_SM to be mounted ..."
                sleep 2
            fi

            if [[ $i -eq 5 ]]; then
                information "showing status of $PATH_FS_SM ..."
                systemctl status mount-server-management.service
                information "--------------------------------------------------------------"
                information "$PATH_FS_SM is not mounted. Please check the status and choose an option:"
                information "1. Continue waiting"
                information "2. Try mounting manually"
                information "3. Exit script"
                read -p "Enter your choice: " choice

                case $choice in
                    1)
                        information "Trying again ..."
                        i=0
                        ;;
                    2)
                        information "Trying without systemd ..."
                        cmd "/usr/bin/sshfs -o allow_other -o IdentityFile=/root/.ssh/id_rsa $FILESHARE_USERNAME@$FILESHARE_HOST:$FILESHARE_HOST_PATH $PATH_FS_SM -o _netdev,follow_symlinks,uid=0,gid=0"
                        # check if PATH_FS_SM is mounted
                        if [[ $(mount | grep $PATH_FS_SM) != "" ]]; then
                            information "$PATH_FS_SM is mounted ..."
                            question_yn "Use this connection or restart systemctl service. Use connection?" "Y"
                            if [[ $? -eq 1 ]]; then
                                information "Use this connection. Systemd service mount has failed ..."
                                sleep 3
                                break
                            else
                                information "Unmounting $PATH_FS_SM ..."
                                cmd "fusermount -u $PATH_FS_SM"
                                i=0
                            fi
                        else
                            information "$PATH_FS_SM is not mounted. Exiting script ..."
                            exit 1
                        fi
                        ;;
                    3)
                        information "Exit script ..."
                        exit 1
                        ;;
                    *)
                        information "Invalid choice. ..."
                        i=4
                        ;;
                esac
            fi
        done
    }


    function create_user_fileshare_mountpoint {
        subsector "Create user fileshare mountpoint"
        PATH_USER_FS="/home/$USERNAME/fileshare"
        if [[ -d $PATH_USER_FS ]]; then
            information "sshfs mountpoint already exists, no need to create again ..."
        else
            information "Creating sshfs mountpoint $PATH_USER_FS ..."
            cmd "mkdir -p $PATH_USER_FS"
        fi
    }


    function create_user_fileshare_server_management_mountpoint {
        subsector "Create user fileshare server-management mountpoint"
        PATH_USER_FS_SM="/home/$USERNAME/fileshare/server-management"
        if [[ -d $PATH_USER_FS_SM ]]; then
            information "sshfs mountpoint already exists, no need to create again ..."
        else
            information "Creating sshfs mountpoint $PATH_USER_FS_SM ..."
            cmd "mkdir -p $PATH_USER_FS_SM"
        fi
    }   


    function  create_mount_sm_user_service {
        subsector "Create systemd user-mount-server-management.service"
        if [[ -f $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/user-mount-server-management.service ]]; then
            information "systemd service user-mount-server-management.service already exists, no need to create again ..."
        else
            information "Creating systemd service user-mount-server-management.service ..."
            WRITE_FILE_SYSTEMD_MOUNT_SERVER_MANAGEMENT_USER
        fi
    }


    function link_mount_sm_user_service {
        subsector "Create link to /etc/systemd/system/"
        if [[ -L /etc/systemd/system/user-mount-server-management.service && -e /etc/systemd/system/user-mount-server-management.service ]]; then
            information "link already exists, no need to create again ..."
        else
            information "Creating link ..."
            cmd "ln -s $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/user-mount-server-management.service /etc/systemd/system/"
        fi
    }


    function enable_and_start_mount_sm_user_service {
        subsector "Enable and start systemd user-mount-server-management.service"
        cmd "systemctl enable --now user-mount-server-management.service"
    }


    function check_mount_sm_user_service {
        subsector "Check if $PATH_USER_FS_SM is mounted"
        for i in {1..5}; do
            if [[ $(mount | grep $PATH_USER_FS_SM) != "" ]]; then
                information "$PATH_USER_FS_SM is mounted ..."
                break
            else
                information "Waiting for $PATH_USER_FS_SM to be mounted ..."
                sleep 2
            fi

            if [[ $i -eq 5 ]]; then
                information "showing status of $PATH_USER_FS_SM ..."
                systemctl status sshfs-fileshare-mount-user.service
                information "--------------------------------------------------------------"
                information "$PATH_USER_FS_SM is not mounted. Please check the status and choose an option:"
                information "1. Continue waiting"
                information "2. Try mounting manually"
                information "3. Exit script"
                read -p "Enter your choice: " choice

                case $choice in
                    1)
                        information "Trying again ..."
                        i=0
                        ;;
                    2)
                        information "Trying without systemd ..."
                        cmd "/usr/bin/sshfs -o allow_other -o IdentityFile=/home/$USERNAME/.ssh/id_rsa $FILESHARE_USERNAME@$FILESHARE_HOST:$FILESHARE_HOST_PATH $PATH_USER_FS_SM -o _netdev,follow_symlinks,uid=1000,gid=1000,allow_other"
                        # check if PATH_USER_FS_SM is mounted
                        if [[ $(mount | grep $PATH_USER_FS_SM) != "" ]]; then
                            information "$PATH_USER_FS_SM is mounted ..."
                            question_yn "Use this connection or restart systemctl service. Use connection?" "Y"
                            if [[ $? -eq 1 ]]; then
                                information "Use this connection. Systemd service mount has failed ..."
                                sleep 3
                                break
                            else
                                information "Unmounting $PATH_USER_FS_SM ..."
                                cmd "fusermount -u $PATH_USER_FS_SM"
                                i=0
                            fi
                        else
                            information "$PATH_USER_FS_SM is not mounted. Exiting script ..."
                            exit 1
                        fi
                        ;;
                    3)
                        information "Exit script ..."
                        exit 1
                        ;;
                    *)
                        information "Invalid choice. ..."
                        i=4
                        ;;
                esac
            fi
        done
    }


    function create_monitoring_mountpoint {
        subsector "Create monitoring mountpoint"
        
        information "Create mount-monitoring.path"
        WRITE_FILE_SYSTEMD_MOUNT_MONITORING_PATH

        information "Create mount-monitoring.service"
        WRITE_FILE_SYSTEMD_MOUNT_MONITORING_SERVICE

        information "Create mount-monitoring.sh"
        WRITE_FILE_SYSTEMD_MOUNT_MONITORING_SH

        information "Setting rights for mount-monitoring.sh ..."
        cmd "chmod +x $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-monitoring.sh"

        information "Link mount-monitoring.path to /etc/systemd/system/"
        cmd "ln -s $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-monitoring.path /etc/systemd/system/"

        information "Link mount-monitoring.service to /etc/systemd/system/"
        cmd "ln -s $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-monitoring.service /etc/systemd/system/"

        information "Enable and start mount-monitoring.path"
        cmd "systemctl enable --now mount-monitoring.path"
    }
    #generate_ssh_keygen
    #copy_fileshare_host_public_key
    create_sshfs_mountpoint
    create_mount_sm_root_service
    link_mount_sm_root_service
    enable_and_start_mount_sm_root_service
    check_mount_sm_root_service
    create_monitoring_mountpoint
    WRITE_FILE_MOUNT_SERVER_MANAGEMENT_COMMANDS
}


function create_file_start_on_host {
    subsector "Create file start-on-host"
    if [[ -f $PATH_SM_SYSTEM/soh-$FOLDER_SERVER_FOLDERNAME ]]; then
        information "start-on-host already exists, no need to create again ..."
    else
        information "Creating start-on-host ..."
        WRITE_FILE_START_ON_HOST
    fi
    information "Setting rights for soh-$FOLDER_SERVER_FOLDERNAME ..."
    cmd "chmod +x $PATH_SM_SYSTEM/soh-$FOLDER_SERVER_FOLDERNAME"
}


function config_fileshare_server_management {
    sector "CONFIGURE FILESHARE SERVER-MANAGEMENT"


    function check_fileshare_server_management_path {
        subsector "create $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME if not exists"

        if [[ ! -d $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME ]]; then
            information "create $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"
            cmd "mkdir $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"
        else
            information "Show content of $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"
            cmd "ls -l $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"
            question_yn "Create a backup and delete content of $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME? (it has to be empty, to continue)" "N"
            if [[ $? -eq 1 ]] ; then
                information "create Backup of $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"
                cmd "cp -r $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME-backup-$(date +"%Y-%m-%d-%H-%M-%S")"
                information "Delete content of $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"
                cmd "rm -r $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME/*"
            else
                information "Exit script ..."
                exit 1
            fi
        fi
    }
    # TODO: create a rsync backup of the content of $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME
    check_fileshare_server_management_path
}


function set_get_host_information {
    sector "SET GET HOST INFORMATION"
    subsector "Create get-host-information"
    WRITE_FILE_GET_HOST_INFORMATION
    information "Setting rights for get-host-information.sh ..."
    cmd "chmod +x $PATH_SM/system-information/script-files/get-host-information"

    subsector "Create get-host-information.service"
    WRITE_FILE_GET_HOST_INFORMATION_SERVICE

    information "Set link to /etc/systemd/system/"
    cmd "ln -s $PATH_SM/system-information/script-files/get-host-information.service /etc/systemd/system/"
        
    subsector "Create get-host-information.timer"
    WRITE_FILE_GET_HOST_INFORMATION_TIMER

    information "Set link to /etc/systemd/system/"
    cmd "ln -s $PATH_SM/system-information/script-files/get-host-information.timer /etc/systemd/system/"

    subsector "Create commands"
    WRITE_FILE_GET_HOST_INFORMATION_COMMANDS

    information "Enable and start get-host-information.timer"
    cmd "systemctl enable --now get-host-information.timer"
}


function set_system_cmds_commands {
    sector "SET SYSTEM CMDS COMMANDS"
    subsector "Create system-cmds-commands"
    information "Create directory information"
    cmd "mkdir -p $PATH_SM/system-cmd/information"
    information "Create directory monitoring"
    cmd "mkdir -p $PATH_SM/system-cmd/monitoring"
    WRITE_FILE_SYSTEM_CMDS_COMMANDS
    information "Setting rights for system-cmds-commands ..."
    cmd "chmod +x $PATH_SM/system-cmd/commands"
}



function copy_server_management_to_fileshare_sm_folder {
    sector "COPY SERVER-MANAGEMENT TO FILESHARE SM FOLDER"
    subsector "Copy $PATH_SM to $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"
    cmd "rsync -aph --update --stats --delete $PATH_SM/ $PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"
} 



#>>>>>>>>>>>>>>HERE<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<HERE<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
# TODO:  delete these functions  
function create_fileshare_paths {
    subsector "Create fileshare paths"
    ARRAY_FS_PATHS=("$PATH_FS_SM/" "$PATH_ROOT_FS_SM_SERVER_NAME/$FOLDER_BACKUP" "$PATH_ROOT_FS_SM_SERVER_NAME/$FOLDER_MONITORING" "$PATH_ROOT_FS_SM_SERVER_NAME/$FOLDER_SERVICES" "$PATH_ROOT_FS_SM_SERVER_NAME/$FOLDER_INFORMATION")
    for path in "${ARRAY_FS_PATHS[@]}"
    do
        cmd "mkdir $path"
    done
}


function copy_to_fileshare_host_data {
    subsector "Copy $FILE_VARIABLES to $PATH_ROOT_FS_SM_SERVER_NAME/$FOLDER_INFORMATION"
    cmd "cp $FILE_VARIABLES $PATH_ROOT_FS_SM_SERVER_NAME/$FOLDER_INFORMATION/"
}
# END TODO: delete these functions

 






#===========================#                                
#>> THIS SCRIPT FUNCTIONS <<#
#===========================#
#
#

function delete_lines {
    local lines=$1
    for ((i=0; i<$lines; i++)); do
        echo -en "\e[1A\e[K"
    done
}

# check if script is executed as root
if [[ $EUID -ne 0 ]]; then
    echo -e "\n\e[91mThis script must be run as root\e[0m"
    exit 1
fi

function wait_continue {
        local i=$1
        while ((i > 0)); do
            echo -ne "$i seconds left\033[0K\r"
            read -n 1 -s -t 1 && { return; }
            ((i--))
        done
}

function sector {
    local sec=3
    echo -en "\n\e[92m$1 "
    echo ""
    for ((i=0; i<${#1}; i++)); do
        echo -n "="
    done
    echo -e "\e[0m\n"
    while ((sec > 0)); do
        sleep 1
        ((sec--))
    done
}

function subsector {
    local sec=1
    echo -en "\n\e[92m$1 "
    while ((sec > 0)); do
        echo -ne "."
        read -n 1 -s -t 1 && { break; }
        ((sec--))
    done
    echo -e "\e[0m"
}

function information {
    # yellow
    echo -e "\e[93m$1\e[0m"
}

function cmd {
    local sec=1
    local command=$1
    echo -e "-> \e[94m$command\e[0m"
    # split command on # if exists 
    if [[ $command == *"#"* ]]; then
        command=$(echo $command | cut -d'#' -f1)
    fi
    sleep $sec
    $command
}

function question_yn {
    standardAnswer=$2
    if [[ $standardAnswer == "N" || $standardAnswer == "n" ]]; then
        textAnswer="y/N"
    fi
    if [[ $standardAnswer == "Y" || $standardAnswer == "y" ]]; then
        textAnswer="Y/n"
    fi
    echo -en "\n\e[92m$1 ($textAnswer)\e[0m " 
    read answer
    if [[ $answer == "" ]]; then
        answer=$standardAnswer
    fi
    # lowercase standardAnswer
    standardAnswer=$(echo $standardAnswer | tr '[:upper:]' '[:lower:]')
    # lowercase answer
    answer=$(echo $answer | tr '[:upper:]' '[:lower:]')

    if [[ $answer == "y" ]]; then
        return 1
    else
        return 0
    fi
}

#function question with return value
function question {
    echo -en "\n\e[92m$1\e[0m "
    read answer
    if [[ $answer == "" ]]; then
        answer=$2
    fi
    echo $answer
}


#==================#
#>> SCRIPT FILES <<#
#==================#
#
#

function WRITE_FILE_HOST_DATA {
    cat > $FILE_VARIABLES << EOF
# variables
USERNAME="$USERNAME"
IP_ADDRESS="$(hostname -I | cut -d' ' -f1)"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
CMD_BACKUP_SYSTEM_BEFORE_UPGRADE=""
CMD_LIST_BACKUPS=""
USER_START_CMDS_ON_HOST="$USER_START_CMDS_ON_HOST"

install_packages=("$INSTALL_PACKAGES")

FOLDER_NOTES="$FOLDER_NOTES"
FOLDER_SYSTEM="$FOLDER_SYSTEM"
FOLDER_MOUNT_SERVER_MANAGEMENT="$FOLDER_MOUNT_SERVER_MANAGEMENT"
FOLDER_SYSTEM_INFORMATION="$FOLDER_SYSTEM_INFORMATION"

PATH_SM="$PATH_SM"
PATH_SM_NOTES="$PATH_SM_NOTES"
PATH_SM_SYSTEM="$PATH_SM_SYSTEM"
PATH_SM_MOUNT_SERVER_MANAGEMENT="$PATH_SM_MOUNT_SERVER_MANAGEMENT"
PATH_SM_SYSTEM_INFORMATION="$PATH_SM/system-information"

FOLDER_SERVER_FOLDERNAME="$FOLDER_SERVER_FOLDERNAME"

PATH_FS="$PATH_FS"
PATH_FS_SM="$PATH_FS_SM"
PATH_FS_SM_FOLDERNAME="$PATH_FS_SM/$FOLDER_SERVER_FOLDERNAME"

FILESHARE_HOST="$FILESHARE_HOST"
FILESHARE_USERNAME="$FILESHARE_USERNAME"
FILESHARE_HOST_PATH="$FILESHARE_HOST_PATH"
EOF
}







function WRITE_FILE_SUPPORT_FUNCTIONS {
    cat > $PATH_SM/_system/support-functions << EOF
function delete_lines {
    local lines=\$1
    for ((i=0; i<\$lines; i++)); do
        echo -en "\e[1A\e[K"
    done
}


function wait_continue {
        local i=\$1
        while ((i > 0)); do
            echo -ne "\$i seconds left\033[0K\r"
            read -n 1 -s -t 1 && { return; }
            ((i--))
        done
}


function sector {
    local sec=5
    echo -en "\n\e[92m\$1 "
    while ((sec > 0)); do
        echo -ne "."
        read -n 1 -s -t 1 && { break; }
        ((sec--))
    done
    echo ""
    for ((i=0; i<\${#1}; i++)); do
        echo -n "="
    done
    echo -e "\e[0m\n"
}


function subsector {
    local sec=3
    echo -en "\n\e[92m\$1 "
    while ((sec > 0)); do
        echo -ne "."
        read -n 1 -s -t 1 && { break; }
        ((sec--))
    done
    echo -e "\e[0m"
}


function information {
    # yellow
    echo -e "\e[93m\$1\e[0m"
}


function cmd {
    local sec=2
    local command=\$1
    echo -e "-> \e[94m\$command\e[0m"
    # split command on # if exists 
    if [[ \$command == *"#"* ]]; then
        command=\$(echo \$command | cut -d'#' -f1)
    fi
    sleep \$sec
    \$command
}


function question_yn {
    standardAnswer=\$2
    if [[ \$standardAnswer == "N" || \$standardAnswer == "n" ]]; then
        textAnswer="y/N"
    fi
    if [[ \$standardAnswer == "Y" || \$standardAnswer == "y" ]]; then
        textAnswer="Y/n"
    fi
    echo -en "\n\e[92m\$1 (\$textAnswer)\e[0m "
    read answer
    if [[ \$answer == "" ]]; then
        answer=\$standardAnswer
    fi
    # lowercase standardAnswer
    standardAnswer=\$(echo \$standardAnswer | tr '[:upper:]' '[:lower:]')
    # lowercase answer
    answer=\$(echo \$answer | tr '[:upper:]' '[:lower:]')

    if [[ \$answer == \$standardAnswer ]]; then
        return 1
    else
        return 0
    fi
}


#function question with return value
function question {
    echo -en "\n\e[92m\$1\e[0m "
    read answer
    if [[ \$answer == "" ]]; then
        answer=\$2
    fi
    echo \$answer
}



function rsync_mount_to_host {
    information "rsync service to \$PATH_SM"
    mydate=\$(date +"%Y-%m-%d_%Hh-%Mm-%Ss")
    cmd "mkdir -p \$PATH_FS_SM_FOLDERNAME/_backups/\$1/\$mydate"
    cmd "cp -r \$PATH_SM/\$1/ \$PATH_FS_SM_FOLDERNAME/_backups/\$1/\$mydate"
    cmd "rsync -aph --update --stats --delete \$PATH_FS_SM_FOLDERNAME/\$1/ \$PATH_SM/\$1"

    # delete folders in PATH_FS_SM_FOLDERNAME/\$1/backup older than 2 days but keep at least 10 backups
    cmd "find \$PATH_FS_SM_FOLDERNAME/_backups/\$1/ -type d -ctime +2 | ls -1tr | head -n -10 | xargs -d '\n' rm -rf"
}


function rsync_info_to_mount {
    information "rsync info to \$PATH_SM/system-information"
    cmd "rsync -aph --update --stats --delete \$PATH_SM/\$1/ \$PATH_FS_SM_FOLDERNAME/\$1"
}
EOF
}


function WRITE_FILE_START_ON_HOST {
    cat > $PATH_SM_SYSTEM/soh-$FOLDER_SERVER_FOLDERNAME << EOF
#!/bin/bash
# this script start services and functions on host

# implement variables of the host on same path
path_host_root=\$(realpath \$0 | rev | cut -d'/' -f3- | rev)
source \$path_host_root/_system/variables
source \$path_host_root/_system/support-functions

# array SERVICES of paths ../* without paths beginning with _ or .
SERVICES=(\$(ls \$path_host_root | grep -v -E "^_|^\."))


# if no parameter is passed, then print usage
if [ \$# -eq 0 ]; then
    echo "SERVICES: \${SERVICES[@]}"
    while true; do
        read -p "Enter the service: " SERVICE
        if [[ " \${SERVICES[@]} " =~ " \${SERVICE} " ]]; then
            break
        else
            information "Invalid service. Please enter a valid service."
        fi
    done

    source \$path_host_root/\$SERVICE/commands get_commands
    COMMANDS=("\${AVAILABLE_COMMANDS[@]}")

    echo "COMMANDS: \${COMMANDS[@]}"
    while true; do
        read -p "Enter the command: " COMMAND
        if [[ " \${COMMANDS[@]} " =~ " \${COMMAND} " ]]; then
            break
        else
            echo "Invalid command. Please enter a valid command."
        fi
    done
else
    SERVICE=\$1
    COMMAND=\$2

    if [[ ! " \${SERVICES[@]} " =~ " \${SERVICE} " ]]; then
        information "Invalid service. Please enter a valid service."
        echo "SERVICES: \${SERVICES[@]}"
        exit 1
    fi
    source \$PATH_FS_SM_FOLDERNAME/\$SERVICE/commands get_commands
    COMMANDS=("\${AVAILABLE_COMMANDS[@]}")
    if [[ ! " \${COMMANDS[@]} " =~ " \${COMMAND} " ]]; then
        information "Invalid command. Please enter a valid command."
        echo "COMMANDS: \${COMMANDS[@]}"
        exit 1
    fi
fi


# if logs folder does not exist, create it
if [[ ! -d \$path_host_root/\$SERVICE/logs/commands ]]; then
    mkdir -p \$path_host_root/\$SERVICE/logs/commands
fi

if [[ \$(ip -br -4 addr show dev \$(ip route | grep default | awk '{print \$5}') | awk '{print \$3}' | cut -d/ -f1) == \$IP_ADDRESS ]]; then
    LOG_OUTPUT=\$PATH_SM/\$SERVICE/monitoring/\$COMMAND-output.log
    LOG_ERROR=\$PATH_SM/\$SERVICE/monitoring/\$COMMAND-error.log
    source \$PATH_FS_SM_FOLDERNAME/\$SERVICE/commands \$COMMAND > >(tee \$LOG_OUTPUT) 2> >(tee \$LOG_ERROR >&2)
    information "execute on host: bash \$PATH_SM/\$SERVICE/commands \$COMMAND"
    information "execute on client: ssh -t \$USER_START_CMDS_ON_HOST@\$IP_ADDRESS \"bash \$PATH_FS_SM_FOLDERNAME/\$FOLDER_SYSTEM/soh-\$FOLDER_SERVER_FOLDERNAME \$SERVICE \$COMMAND\""
else
    information "execute on client: ssh -t \$USER_START_CMDS_ON_HOST@\$IP_ADDRESS \"bash \$PATH_FS_SM_FOLDERNAME/\$FOLDER_SYSTEM/soh-\$FOLDER_SERVER_FOLDERNAME \$SERVICE \$COMMAND\""

    ssh -t \$USER_START_CMDS_ON_HOST@\$IP_ADDRESS "bash \$PATH_FS_SM_FOLDERNAME/\$FOLDER_SYSTEM/soh-\$FOLDER_SERVER_FOLDERNAME \$SERVICE \$COMMAND"
fi
EOF
}




function WRITE_FILE_MOUNT_SERVER_MANAGEMENT_COMMANDS {
    cat > $PATH_SM_MOUNT_SERVER_MANAGEMENT/commands << EOF

function get_commands {
    AVAILABLE_COMMANDS=("setup" "update" "start" "stop" "restart" "status" "logs")
}

function setup {
    information "setup"

    # rsync service from fileshare to host
    rsync_mount_to_host \$SERVICE


    # Link mount-server-management.service to /etc/systemd/system/ if not exists
    if [[ -L /etc/systemd/system/mount-server-management.service && -e /etc/systemd/system/mount-server-management.service ]]; then
        information "link already exists, no need to create again ..."
    else
        information "Creating link ..."
        cmd "sudo ln -s \$PATH_SM/\$SERVICE/script-files/mount-server-management.service /etc/systemd/system/"
    fi

    # enable and start mount-server-management.service
    information "Enable and start mount-server-management.service"
    cmd "sudo systemctl enable --now mount-server-management.service"

    # link user-mount-server-management.service to /etc/systemd/system/ if not exists
    if [[ -L /etc/systemd/system/user-mount-server-management.service && -e /etc/systemd/system/user-mount-server-management.service ]]; then
        information "link already exists, no need to create again ..."
    else
        information "Creating link ..."
        cmd "sudo ln -s \$PATH_SM/\$SERVICE/script-files/user-mount-server-management.service /etc/systemd/system/"
    fi

    # enable and start user-mount-server-management.service
    information "Enable and start user-mount-server-management.service"
    cmd "sudo systemctl enable --now user-mount-server-management.service"

    # Link mount-monitoring.path to /etc/systemd/system/ if not exists
    if [[ -L /etc/systemd/system/mount-monitoring.path && -e /etc/systemd/system/mount-monitoring.path ]]; then
        information "link already exists, no need to create again ..."
    else
        information "Creating link ..."
        cmd "sudo ln -s \$PATH_SM/\$SERVICE/script-files/mount-monitoring.path /etc/systemd/system/"
    fi

    # Link mount-monitoring.service to /etc/systemd/system/ if not exists
    if [[ -L /etc/systemd/system/mount-monitoring.service && -e /etc/systemd/system/mount-monitoring.service ]]; then
        information "link already exists, no need to create again ..."
    else
        information "Creating link ..."
        cmd "sudo ln -s \$PATH_SM/\$SERVICE/script-files/mount-monitoring.service /etc/systemd/system/"
    fi

    # enable and start mount-monitoring.path
    information "Enable and start mount-monitoring.path"
    cmd "sudo systemctl enable --now mount-monitoring.path"


}

function update {
    information "update"

    rsync_mount_to_host \$SERVICE
    
    # daemon-reload
    cmd "sudo systemctl daemon-reload"

    # restart mount-server-management.service
    information "Restart mount-server-management.service"
    cmd "sudo systemctl restart mount-server-management.service"

    # restart user-mount-server-management.service
    information "Restart user-mount-server-management.service"
    cmd "sudo systemctl restart user-mount-server-management.service"

    # restart mount-monitoring.path
    information "Restart mount-monitoring.path"
    cmd "sudo systemctl restart mount-monitoring.path"
}

function start {
    information "start"

    # start mount-server-management.service
    information "Start mount-server-management.service"
    cmd "sudo systemctl start mount-server-management.service"

    # start user-mount-server-management.service
    information "Start user-mount-server-management.service"
    cmd "sudo systemctl start user-mount-server-management.service"

    # start mount-monitoring.path
    information "Start mount-monitoring.path"
    cmd "sudo systemctl start mount-monitoring.path"
}


function status {
    information "status"

    # status mount-server-management.service
    information "Status mount-server-management.service"
    cmd "sudo systemctl status mount-server-management.service"

    # status user-mount-server-management.service
    information "Status user-mount-server-management.service"
    cmd "sudo systemctl status user-mount-server-management.service"

    # status mount-monitoring.path
    information "Status mount-monitoring.path"
    cmd "sudo systemctl status mount-monitoring.path"
}


function restart {
    information "restart"

    # restart mount-server-management.service
    information "Restart mount-server-management.service"
    cmd "sudo systemctl restart mount-server-management.service"

    # restart user-mount-server-management.service
    information "Restart user-mount-server-management.service"
    cmd "sudo systemctl restart user-mount-server-management.service"

    # restart mount-monitoring.path
    information "Restart mount-monitoring.path"
    cmd "sudo systemctl restart mount-monitoring.path"
}


function stop {
    information "stop"

    # stop mount-server-management.service
    information "Stop mount-server-management.service"
    cmd "sudo systemctl stop mount-server-management.service"

    # stop user-mount-server-management.service
    information "Stop user-mount-server-management.service"
    cmd "sudo systemctl stop user-mount-server-management.service"

    # stop mount-monitoring.path
    information "Stop mount-monitoring.path"
    cmd "sudo systemctl stop mount-monitoring.path"
}

# start \$1 as command-function
\$1

EOF
}




function WRITE_FILE_SYSTEMD_MOUNT_MONITORING_PATH {
    cat > $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-monitoring.path << EOF
[Unit]
Description=Monitor sshfs fileshare
After=network.target

[Path]
PathExists=$PATH_FS_SM_FOLDERNAME
PathExists=!$PATH_FS_SM_FOLDERNAME
#PathExists=/home/$USERNAME/fileshare/server-management/$FOLDER_SERVER_FOLDERNAME
#PathExists=!/home/$USERNAME/fileshare/server-management/$FOLDER_SERVER_FOLDERNAME
Unit=mount-monitoring.service

[Install]
WantedBy=multi-user.target
EOF
}


function WRITE_FILE_SYSTEMD_MOUNT_MONITORING_SERVICE {
    cat > $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-monitoring.service << EOF
[Unit]
Description=Monitor sshfs fileshare
After=network.target

[Service]
Type=exec
ExecStart=$PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-monitoring.sh

[Install]
WantedBy=multi-user.target
EOF
}




function WRITE_FILE_SYSTEMD_MOUNT_MONITORING_SH {
    cat > $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-monitoring.sh << EOF
#!/bin/bash
# this script is executed by systemd mount-monitoring.service

# implement variables of the host on same path
source $PATH_SM_SYSTEM/variables
source \$PATH_SM_SYSTEM/support-functions

# if logs folder does not exist, create it
if [[ ! -d \$PATH_SM_MOUNT_SERVER_MANAGEMENT/logs ]]; then
    mkdir -p \$PATH_SM_MOUNT_SERVER_MANAGEMENT/logs
fi

# if mount-monitoring.log does not exist, create it
if [[ ! -f \$PATH_SM_MOUNT_SERVER_MANAGEMENT/logs/mount-monitoring.log ]]; then
    touch \$PATH_SM_MOUNT_SERVER_MANAGEMENT/logs/mount-monitoring.log
fi

log_entry="\$(date +"%Y-%m-%d-%H-%M-%S") - \$PATH_FS_SM - "
if [[ \$(mount | grep \$PATH_FS_SM) != "" ]]; then
    log_entry+="is mounted"
else
    log_entry+="is not mounted"
fi

echo \$log_entry >> \$PATH_SM_MOUNT_SERVER_MANAGEMENT/logs/mount-monitoring.log

cmd "\$log_entry > \$PATH_SM_MOUNT_SERVER_MANAGEMENT/monitoring/mount-monitoring-status.log"
#cmd "systemctl status mount-monitoring.service >> \$PATH_SM_MOUNT_SERVER_MANAGEMENT/monitoring/mount-monitoring-status.log"
EOF
}




function WRITE_FILE_SYSTEMD_MOUNT_SERVER_MANAGEMENT_ROOT {
    cat > $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/mount-server-management.service << EOF
[Unit]
Description=Mount sshfs fileshare
After=network.target

[Service]
Type=exec
ExecStart=/usr/bin/sshfs -o allow_other -o IdentityFile=/root/.ssh/id_rsa $FILESHARE_USERNAME@$FILESHARE_HOST:$FILESHARE_HOST_PATH $PATH_FS_SM -o _netdev,follow_symlinks,uid=0,gid=0
ExecStop=/bin/fusermount -u $PATH_FS_SM
RemainAfterExit=yes
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
}






function WRITE_FILE_SYSTEMD_MOUNT_SERVER_MANAGEMENT_USER {
    cat > $PATH_SM_MOUNT_SERVER_MANAGEMENT/script-files/user-mount-server-management.service << EOF
[Unit]
Description=Mount sshfs fileshare
After=network.target

[Service]
Type=exec
ExecStart=/usr/bin/sshfs -o allow_other -o IdentityFile=/home/$USERNAME/.ssh/id_rsa $FILESHARE_USERNAME@$FILESHARE_HOST:$FILESHARE_HOST_PATH $PATH_USER_FS_SM -o _netdev,follow_symlinks,uid=1000,gid=1000,allow_other
ExecStop=/bin/fusermount -u $PATH_USER_FS_SM
RemainAfterExit=yes
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
}

function WRITE_FILE_GET_HOST_INFORMATION {
    cat > $PATH_SM/system-information/script-files/get-host-information << EOF
#!/bin/bash
source $PATH_SM_SYSTEM/variables
source \$PATH_SM_SYSTEM/support-functions

service=system-information

infoFile=system-information.log
bootErrorFile=boot-errors.log
bootEmergencyFile=boot-only-emergency-Alerts.log
bootCriticalFile=boot-only-critical-Alerts.log
availableUpgradesFile=available-upgrades.log

pathLogs=\$PATH_SM/system-information/logs
pathMonitoring=\$PATH_SM/system-information/monitoring
pathLogsArchive=\$PATH_SM/system-information/logs/archive

updateDate=\$(date +"%Y-%m-%d-%H-%M-%S")
hostName=\$(hostname)
ipAddress=\$(hostname -I | cut -d' ' -f1)
uptimeTime=\$(uptime -p)
uptimeDate=\$(uptime -s)
lastUpgradeDate=\$(ls -l /var/log/apt | grep history.log | awk '{print \$6,\$7,\$8}')
countOfAvailableDistUpgrades=\$((\$(apt list --upgradable 2>/dev/null | wc -l)-1)) # this works also -> apt-get dist-upgrade -s 2>/dev/null | grep 'Inst' | wc -l
countLastBootWarningErrors04=\$((\$(journalctl -b 0 -p 0..4 | wc -l)-1))
countLastBootEmergencyAlerts01=\$((\$(journalctl -b 0 -p 0..1 | wc -l)-1))
countLastBootCriticalAlerts2=\$((\$(journalctl -b 0 -p 2 | wc -l)-1))
countRunProcesses=\$((\$(ps -e | wc -l)-1))

row="\$updateDate | Hostname: \$hostName | IP-Address: \$ipAddress | Uptime: \$uptimeTime | Warnings: \$countLastBootWarningErrors04 | Errors: \$countLastBootCriticalAlerts2 | Critical Errors: \$countLastBootEmergencyAlerts01 | Upgrades: \$countOfAvailableDistUpgrades | Processes: \$countRunProcesses"

if [[ ! -f \$pathLogs/\$infoFile ]]; then
    echo \$row > \$pathLogs/\$infoFile
else
    echo \$row >> \$pathLogs/\$infoFile
fi

journalctl -p 0..4 > \$pathLogs/all-warning-errors.log
journalctl -b -p 0..1 > \$pathLogs/critical-errors.log
journalctl -b -p 2 > \$pathLogs/errors.log
apt list --upgradable 2>/dev/null > \$pathLogs/available-upgrades.log

rsync_info_to_mount \$service/logs
EOF
}



function WRITE_FILE_GET_HOST_INFORMATION_SERVICE {
    cat > $PATH_SM/system-information/script-files/get-host-information.service << EOF
[Unit]
Description=Get host information
After=network.target

[Service]
Type=exec
ExecStart=/bin/bash $PATH_SM/system-information/script-files/get-host-information
RemainAfterExit=no
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
}



function WRITE_FILE_GET_HOST_INFORMATION_TIMER {
    cat > $PATH_SM/system-information/script-files/get-host-information.timer << EOF
[Unit]
Description=Run get-host-information.service every day

[Timer]
OnCalendar=*-*-* 00:05:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
}



function WRITE_FILE_GET_HOST_INFORMATION_COMMANDS {
    cat > $PATH_SM/system-information/commands << EOF
function get_commands {
    AVAILABLE_COMMANDS=("setup" "update" "test" "start" "stop" "restart" "status" "logs")
}



function setup {
    information "setup"

    # rsync service from fileshare to host
    rsync_mount_to_host \$SERVICE

    # Link get-host-information.service to /etc/systemd/system/ if not exists
    if [[ -L /etc/systemd/system/get-host-information.service && -e /etc/systemd/system/get-host-information.service ]]; then
        information "link already exists, no need to create again ..."
    else
        information "Creating link ..."
        cmd "sudo ln -s \$PATH_SM/\$SERVICE/script-files/get-host-information.service /etc/systemd/system/"
    fi

    # Link get-host-information.timer to /etc/systemd/system/ if not exists
    if [[ -L /etc/systemd/system/get-host-information.timer && -e /etc/systemd/system/get-host-information.timer ]]; then
        information "link already exists, no need to create again ..."
    else
        information "Creating link ..."
        cmd "sudo ln -s \$PATH_SM/\$SERVICE/script-files/get-host-information.timer /etc/systemd/system/"
    fi

    # enable and start get-host-information.timer
    information "Enable and start get-host-information.timer"
    cmd "sudo systemctl enable --now get-host-information.timer"
}



function update {
    information "update"

    rsync_mount_to_host \$SERVICE

    # daemon-reload
    cmd "sudo systemctl daemon-reload"

    # restart get-host-information.timer
    information "Restart get-host-information.timer"
    cmd "sudo systemctl restart get-host-information.timer"

    # start get-host-information.service
    information "Start get-host-information.service"
    cmd "sudo systemctl start get-host-information.service"
}



function start {
    information "start"

    # start get-host-information.service
    information "Start get-host-information.service"
    cmd "sudo systemctl start get-host-information.service"
}



function status {
    information "status"

    # status get-host-information.service
    information "Status get-host-information.service"
    cmd "sudo systemctl status get-host-information.service"

    # status get-host-information.timer
    information "Status get-host-information.timer"
    cmd "sudo systemctl status get-host-information.timer"
}



function restart {
    information "restart"

    # restart get-host-information.timer
    information "Restart get-host-information.timer"
    cmd "sudo systemctl restart get-host-information.timer"

    # restart get-host-information.service
    information "Restart get-host-information.service"
    cmd "sudo systemctl restart get-host-information.service"
}



function stop {
    information "stop"

    # stop get-host-information.timer
    information "Stop get-host-information.timer"
    cmd "sudo systemctl stop get-host-information.timer"
}



# start \$1 as command-function
\$1
EOF
}



function WRITE_FILE_SYSTEM_CMDS_COMMANDS {
    cat > $PATH_SM/system-cmd/commands << EOF
function get_commands {
    AVAILABLE_COMMANDS=("setup" "update_os" "update_system" "update_service")
}


function backup_system {
    information "backup_system"
    cmd "\$CMD_BACKUP_SYSTEM_BEFORE_UPGRADE"
    information "Backup is done ..."
    information "List backups ..."
    cmd "\$CMD_LIST_BACKUPS"

    question_yn "Is the backup done correctly?" "N"
    if [[ \$? -eq 1 ]] ; then
        return true
    else
        return false
    fi
}

function setup {
    information "setup"
    information " Here is the command for backup the system before upgrade: \$CMD_BACKUP_SYSTEM_BEFORE_UPGRADE"
    
    question_yn "Would you like to change the command?" "N"
    if [[ \$? -eq 1 ]] ; then
        information "Enter the command for backup the system before upgrade"
        read -p "Enter the command: " CMD_BACKUP_SYSTEM_BEFORE_UPGRADE

        question_yn "Save the command?" "Y"
        if [[ \$? -eq 1 ]]; then
            information "Save the command ..."
            # change variable in variables file
            sed -i "s/CMD_BACKUP_SYSTEM_BEFORE_UPGRADE=.*/CMD_BACKUP_SYSTEM_BEFORE_UPGRADE=\"\$CMD_BACKUP_SYSTEM_BEFORE_UPGRADE\"/g" \$FILE_VARIABLES
        fi
    fi

    information "Here is the command for list backups: \$CMD_LIST_BACKUPS"
    question_yn "Would you like to change the command?" "N"
    if [[ \$? -eq 1 ]] ; then
        information "Enter the command for list backups"
        read -p "Enter the command: " CMD_LIST_BACKUPS

    question_yn "Save the command?" "Y"
        if [[ \$? -eq 1 ]]; then
            information "Save the command ..."
            # change variable in variables file
            sed -i "s/CMD_LIST_BACKUPS=.*/CMD_LIST_BACKUPS=\"\$CMD_LIST_BACKUPS\"/g" \$FILE_VARIABLES
        fi
    fi

}


function update_os {
    information "update_os"
    if [[ backup_system ]]; then
        information "backup is done correctly"
        defaultAnswer="Y"
    else
        information "Backup is not done correctly."
        defaultAnswer="N"
    fi

    question_yn "Would you like to update the system?" "\$defaultAnswer"
    if [[ \$? -eq 1 ]]; then
        information "update_os"
        cmd "apt-get update"
        cmd "apt-get upgrade -y"
        cmd "apt-get dist-upgrade -y"
        cmd "apt-get autoremove -y"
        cmd "apt-get autoclean -y"
    else
        information "Exit without update ..."
        exit 1
    fi
}


function update_system {
    information "write your code to update all relevant services. Then you have to update the service first, to integrate the functions into the host."
}



function update_service {
    information "update service to host"
    rsync_mount_to_host \$SERVICE
}
EOF
}



#====================#
#>>> MAIN PROCESS <<<#
#====================#
#
#


main_process


