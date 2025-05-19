#!/bin/bash

# WordPress Security Audit Script v1.1
# This script gathers information about WordPress installations to help identify security issues
# Run this script from the directory containing your WordPress installation

# Set output file
OUTPUT_FILE="wp_security_audit_$(date +%Y%m%d_%H%M%S).txt"
SCRIPT_VERSION="1.1"
GITHUB_URL="https://raw.githubusercontent.com/ait88/VPS/refs/heads/main/wp-security-audit.sh"

# Function to update the script from GitHub
update_script() {
    echo "Checking for updates..."
    if command -v curl &> /dev/null; then
        LATEST_SCRIPT=$(curl -s "$GITHUB_URL")
    elif command -v wget &> /dev/null; then
        LATEST_SCRIPT=$(wget -q -O - "$GITHUB_URL")
    else
        echo "Neither curl nor wget is available. Cannot check for updates."
        return 1
    fi
    
    if [ -z "$LATEST_SCRIPT" ]; then
        echo "Failed to download the latest script."
        return 1
    fi
    
    # Extract version from the downloaded script
    LATEST_VERSION=$(echo "$LATEST_SCRIPT" | grep "SCRIPT_VERSION=" | head -1 | cut -d'"' -f2)
    
    if [ -z "$LATEST_VERSION" ]; then
        echo "Could not determine latest version."
        return 1
    fi
    
    if [ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]; then
        echo "New version available: $LATEST_VERSION (current: $SCRIPT_VERSION)"
        echo "Updating script..."
        echo "$LATEST_SCRIPT" > "$0"
        chmod +x "$0"
        echo "Script updated successfully. Please run it again."
        exit 0
    else
        echo "You are running the latest version: $SCRIPT_VERSION"
    fi
}

# Function to check if a file contains suspicious patterns
check_suspicious_patterns() {
    local file="$1"
    local suspicious=false
    
    # Common malware patterns
    grep -l "base64_decode\|eval(" "$file" > /dev/null 2>&1 && suspicious=true
    grep -l "<?php" "$file" | grep -v ".php$" > /dev/null 2>&1 && suspicious=true
    
    if $suspicious; then
        echo "SUSPICIOUS: $file"
    fi
}

# Function to detect WordPress installations
detect_wordpress() {
    local dir="$1"
    local is_wordpress=false
    
    # Basic checks for WordPress files
    if [ -f "$dir/wp-config.php" ]; then
        is_wordpress=true
        echo "WordPress detected (wp-config.php exists)"
    elif [ -d "$dir/wp-includes" ] && [ -d "$dir/wp-admin" ]; then
        is_wordpress=true
        echo "WordPress detected (wp-includes and wp-admin directories exist)"
    elif [ -f "$dir/wp-login.php" ]; then
        is_wordpress=true
        echo "WordPress detected (wp-login.php exists)"
    else
        echo "No WordPress installation detected in $dir"
    fi
    
    return $([ "$is_wordpress" = true ] && echo 0 || echo 1)
}

# Function to get WordPress version
get_wp_version() {
    local wp_dir="$1"
    if [ -f "$wp_dir/wp-includes/version.php" ]; then
        grep "wp_version =" "$wp_dir/wp-includes/version.php" | head -1 | cut -d"'" -f2
    else
        echo "Unknown"
    fi
}

# Function to get plugin information
get_plugins_info() {
    local wp_dir="$1"
    local plugins_dir="$wp_dir/wp-content/plugins"
    
    if [ ! -d "$plugins_dir" ]; then
        echo "No plugins directory found"
        return
    fi
    
    echo "List of installed plugins:"
    for plugin in "$plugins_dir"/*; do
        if [ -d "$plugin" ]; then
            plugin_name=$(basename "$plugin")
            version="Unknown"
            
            # Try to get version from the main plugin file
            main_file="$plugin/$plugin_name.php"
            if [ ! -f "$main_file" ]; then
                # Find the main plugin file
                main_file=$(grep -l "Plugin Name:" "$plugin"/*.php 2>/dev/null | head -1)
            fi
            
            if [ -f "$main_file" ]; then
                version=$(grep "Version:" "$main_file" | head -1 | sed 's/.*Version: *\([^ ]*\).*/\1/')
                if [ -z "$version" ]; then
                    version="Unknown"
                fi
            fi
            
            echo "  - $plugin_name (Version: $version)"
            
            # Get the last modified date of the plugin directory
            last_modified=$(find "$plugin" -type f -name "*.php" -exec stat -c "%y" {} \; 2>/dev/null | sort -r | head -1)
            if [ ! -z "$last_modified" ]; then
                echo "    Last modified: $last_modified"
            fi
        fi
    done
}

# Function to get theme information
get_themes_info() {
    local wp_dir="$1"
    local themes_dir="$wp_dir/wp-content/themes"
    
    if [ ! -d "$themes_dir" ]; then
        echo "No themes directory found"
        return
    fi
    
    echo "List of installed themes:"
    for theme in "$themes_dir"/*; do
        if [ -d "$theme" ]; then
            theme_name=$(basename "$theme")
            version="Unknown"
            
            # Try to get version from the style.css file
            if [ -f "$theme/style.css" ]; then
                version=$(grep "Version:" "$theme/style.css" | head -1 | sed 's/.*Version: *\([^ ]*\).*/\1/')
                if [ -z "$version" ]; then
                    version="Unknown"
                fi
            fi
            
            echo "  - $theme_name (Version: $version)"
            
            # Get the last modified date of the theme directory
            last_modified=$(find "$theme" -type f -name "*.php" -exec stat -c "%y" {} \; 2>/dev/null | sort -r | head -1)
            if [ ! -z "$last_modified" ]; then
                echo "    Last modified: $last_modified"
            fi
        fi
    done
}

# Function to check for recently modified files
check_recent_files() {
    local wp_dir="$1"
    local days="$2"
    
    echo "Files modified in the last $days days:"
    find "$wp_dir" -type f -mtime -"$days" 2>/dev/null | sort -r | while read file; do
        echo "  - $file ($(stat -c "%y" "$file" 2>/dev/null))"
        # Check for suspicious patterns in recently modified PHP files
        if [[ "$file" == *.php ]]; then
            check_suspicious_patterns "$file"
        fi
    done
}

# Function to extract database credentials
get_db_credentials() {
    local wp_dir="$1"
    local wp_config="$wp_dir/wp-config.php"
    
    if [ ! -f "$wp_config" ]; then
        echo "No wp-config.php found"
        return
    fi
    
    echo "Database information (partial for security):"
    db_host=$(grep "DB_HOST" "$wp_config" | sed "s/.*'\(.*\)'.*/\1/" | sed 's/.\{2\}$//')
    db_name=$(grep "DB_NAME" "$wp_config" | sed "s/.*'\(.*\)'.*/\1/" | sed 's/.\{2\}$//')
    db_user=$(grep "DB_USER" "$wp_config" | sed "s/.*'\(.*\)'.*/\1/" | sed 's/.\{2\}$//')
    
    echo "  - DB Host: ${db_host}** (masked for security)"
    echo "  - DB Name: ${db_name}** (masked for security)"
    echo "  - DB User: ${db_user}** (masked for security)"
    
    # Check for authentication unique keys and salts
    if grep -q "AUTH_KEY" "$wp_config" && grep -q "SECURE_AUTH_KEY" "$wp_config"; then
        echo "  - Security keys are defined: Yes"
    else
        echo "  - Security keys are defined: No (SECURITY RISK)"
    fi
}

# Function to check for common security issues
check_security_issues() {
    local wp_dir="$1"
    
    echo "Security check:"
    
    # Check directory permissions
    if [ -d "$wp_dir" ]; then
        dir_perms=$(stat -c "%a" "$wp_dir" 2>/dev/null)
        if [ "$dir_perms" == "777" ]; then
            echo "  - WordPress directory has insecure permissions (777)"
        fi
    fi
    
    # Check wp-config.php permissions
    if [ -f "$wp_dir/wp-config.php" ]; then
        config_perms=$(stat -c "%a" "$wp_dir/wp-config.php" 2>/dev/null)
        if [ "$config_perms" == "777" ] || [ "$config_perms" == "666" ]; then
            echo "  - wp-config.php has insecure permissions ($config_perms)"
        fi
    fi
    
    # Check for debug mode
    if [ -f "$wp_dir/wp-config.php" ] && grep -q "WP_DEBUG.*true" "$wp_dir/wp-config.php"; then
        echo "  - WP_DEBUG is enabled (potential security risk)"
    fi
    
    # Check for file editor
    if [ -f "$wp_dir/wp-config.php" ] && grep -q "DISALLOW_FILE_EDIT.*false" "$wp_dir/wp-config.php"; then
        echo "  - File editing is enabled (potential security risk)"
    fi
    
    # Check for suspicious files in uploads
    if [ -d "$wp_dir/wp-content/uploads" ]; then
        php_in_uploads=$(find "$wp_dir/wp-content/uploads" -name "*.php" -type f 2>/dev/null | wc -l)
        if [ "$php_in_uploads" -gt 0 ]; then
            echo "  - Found $php_in_uploads PHP files in uploads directory (potential malware)"
            find "$wp_dir/wp-content/uploads" -name "*.php" -type f 2>/dev/null | head -5 | while read file; do
                echo "    - $file"
            done
        fi
    fi
    
    # Check for common backdoor filenames
    suspicious_files=$(find "$wp_dir" -type f -name "*.ico.php" -o -name "*.png.php" -o -name "*.jpg.php" -o -name "*shell*.php" 2>/dev/null | wc -l)
    if [ "$suspicious_files" -gt 0 ]; then
        echo "  - Found $suspicious_files suspiciously named files (potential backdoors)"
        find "$wp_dir" -type f -name "*.ico.php" -o -name "*.png.php" -o -name "*.jpg.php" -o -name "*shell*.php" 2>/dev/null | head -5 | while read file; do
            echo "    - $file"
        done
    fi
}

# Main function to run the audit
run_audit() {
    # Get current directory
    current_dir=$(pwd)
    echo "Current directory: $current_dir"
    
    # List directory contents to verify we can see WordPress files
    echo "Directory listing:"
    ls -la | head -20
    echo "(showing first 20 entries only)"
    echo ""
    
    # Check for WordPress in current directory
    echo "Checking for WordPress in current directory..."
    if detect_wordpress "$current_dir"; then
        # WordPress found in current directory
        echo "Analyzing WordPress installation in current directory..."
        wp_dir="$current_dir"
        
        echo "WordPress Version: $(get_wp_version "$wp_dir")"
        echo ""
        
        get_plugins_info "$wp_dir"
        echo ""
        
        get_themes_info "$wp_dir"
        echo ""
        
        get_db_credentials "$wp_dir"
        echo ""
        
        check_security_issues "$wp_dir"
        echo ""
        
        check_recent_files "$wp_dir" 7
        echo ""
    else
        # Try to find WordPress installations in subdirectories
        echo "Looking for WordPress installations in subdirectories..."
        found_wp=false
        
        # Simple approach to find WordPress directories
        for dir in $(find "$current_dir" -type d -maxdepth 2 2>/dev/null); do
            if [ -f "$dir/wp-config.php" ]; then
                echo "Found WordPress at: $dir"
                found_wp=true
                
                echo "Analyzing WordPress installation at: $dir"
                wp_dir="$dir"
                
                echo "WordPress Version: $(get_wp_version "$wp_dir")"
                echo ""
                
                get_plugins_info "$wp_dir"
                echo ""
                
                get_themes_info "$wp_dir"
                echo ""
                
                get_db_credentials "$wp_dir"
                echo ""
                
                check_security_issues "$wp_dir"
                echo ""
                
                check_recent_files "$wp_dir" 7
                echo ""
            fi
        done
        
        if [ "$found_wp" = false ]; then
            echo "No WordPress installations found in $current_dir or immediate subdirectories"
        fi
    fi
}

# Check for update flag
if [ "$1" == "--update" ]; then
    update_script
    exit 0
fi

# Run the audit and save to file
{
    echo "WordPress Security Audit v$SCRIPT_VERSION"
    echo "Date: $(date)"
    echo "Server: $(hostname)"
    echo ""
    
    run_audit
    
    echo ""
    echo "Audit complete - Data saved to $OUTPUT_FILE"
} | tee "$OUTPUT_FILE"

echo "Audit complete! Results saved to $OUTPUT_FILE"
echo "To check for script updates, run: $0 --update"