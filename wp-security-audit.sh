#!/bin/bash

# WordPress Security Audit Script
# This script gathers information about WordPress installations to help identify security issues
# Run this script from the parent directory of your WordPress installations

# Set output file
OUTPUT_FILE="wp_security_audit_$(date +%Y%m%d_%H%M%S).txt"

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
            last_modified=$(find "$plugin" -type f -name "*.php" -exec stat -c "%y" {} \; | sort -r | head -1)
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
            last_modified=$(find "$theme" -type f -name "*.php" -exec stat -c "%y" {} \; | sort -r | head -1)
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
    find "$wp_dir" -type f -mtime -"$days" | sort -r | while read file; do
        echo "  - $file ($(stat -c "%y" "$file"))"
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
        dir_perms=$(stat -c "%a" "$wp_dir")
        if [ "$dir_perms" == "777" ]; then
            echo "  - WordPress directory has insecure permissions (777)"
        fi
    fi
    
    # Check wp-config.php permissions
    if [ -f "$wp_dir/wp-config.php" ]; then
        config_perms=$(stat -c "%a" "$wp_dir/wp-config.php")
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
        php_in_uploads=$(find "$wp_dir/wp-content/uploads" -name "*.php" -type f | wc -l)
        if [ "$php_in_uploads" -gt 0 ]; then
            echo "  - Found $php_in_uploads PHP files in uploads directory (potential malware)"
            find "$wp_dir/wp-content/uploads" -name "*.php" -type f | head -5 | while read file; do
                echo "    - $file"
            done
        fi
    fi
    
    # Check for common backdoor filenames
    suspicious_files=$(find "$wp_dir" -type f -name "*.ico.php" -o -name "*.png.php" -o -name "*.jpg.php" -o -name "*shell*.php" | wc -l)
    if [ "$suspicious_files" -gt 0 ]; then
        echo "  - Found $suspicious_files suspiciously named files (potential backdoors)"
        find "$wp_dir" -type f -name "*.ico.php" -o -name "*.png.php" -o -name "*.jpg.php" -o -name "*shell*.php" | head -5 | while read file; do
            echo "    - $file"
        done
    fi
}

# Function to find common access points or patterns
check_common_patterns() {
    local wp_dirs=("$@")
    local common_plugins=()
    local common_themes=()
    
    echo "Checking for common patterns across sites..."
    
    # Parse and analyze plugin data
    for wp_dir in "${wp_dirs[@]}"; do
        if [ -d "$wp_dir/wp-content/plugins" ]; then
            for plugin in "$wp_dir/wp-content/plugins"/*; do
                if [ -d "$plugin" ]; then
                    plugin_name=$(basename "$plugin")
                    if [[ ! " ${common_plugins[@]} " =~ " ${plugin_name} " ]]; then
                        common_plugins+=("$plugin_name")
                    fi
                fi
            done
        fi
        
        if [ -d "$wp_dir/wp-content/themes" ]; then
            for theme in "$wp_dir/wp-content/themes"/*; do
                if [ -d "$theme" ]; then
                    theme_name=$(basename "$theme")
                    if [[ ! " ${common_themes[@]} " =~ " ${theme_name} " ]]; then
                        common_themes+=("$theme_name")
                    fi
                fi
            done
        fi
    done
    
    echo "Common plugins across sites: ${common_plugins[@]}"
    echo "Common themes across sites: ${common_themes[@]}"
}

# Main function to run the audit
run_audit() {
    # Check if working in home directory
    current_dir=$(pwd)
    echo "Current directory: $current_dir"
    
    # Find all WordPress installations
    echo "Finding WordPress installations in $current_dir..."
    # First check if wp-config.php exists in the current directory
    if [ -f "$current_dir/wp-config.php" ]; then
        wp_dirs+=("$current_dir")
        echo "Found WordPress at: $current_dir"
    fi
    wp_dirs=()
    
    # Look for wp-config.php files to identify WordPress installations
    # Using a simpler approach that's more compatible with restricted environments
    for config_file in $(find "$current_dir" -name "wp-config.php" -type f); do
        wp_dir=$(dirname "$config_file")
        wp_dirs+=("$wp_dir")
        echo "Found WordPress at: $wp_dir"
    done
    
    if [ ${#wp_dirs[@]} -eq 0 ]; then
        echo "No WordPress installations found in $current_dir"
        exit 1
    fi
    
    echo "Found ${#wp_dirs[@]} WordPress installations"
    
    # Process each WordPress installation
    for wp_dir in "${wp_dirs[@]}"; do
        echo "=========================================="
        echo "Analyzing WordPress at: $wp_dir"
        echo "=========================================="
        
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
    done
    
    # Check for common patterns across sites
    check_common_patterns "${wp_dirs[@]}"
}

# Run the audit and save to file
{
    echo "WordPress Security Audit"
    echo "Date: $(date)"
    echo "Server: $(hostname)"
    echo ""
    
    run_audit
    
    echo ""
    echo "Audit complete - Data saved to $OUTPUT_FILE"
} | tee "$OUTPUT_FILE"

echo "Audit complete! Results saved to $OUTPUT_FILE"
