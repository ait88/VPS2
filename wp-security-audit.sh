#!/bin/bash

# WordPress Security Audit Script v1.1
# This script gathers information about WordPress installations to help identify security issues
# Run this script from the directory containing your WordPress installation

# Set up script variables
SCRIPT_VERSION="1.1"
GITHUB_URL="https://raw.githubusercontent.com/ait88/VPS/refs/heads/main/wp-security-audit.sh"
FIX_ISSUES=false
FORCE_UPDATE=false

# Set output file with domain name
# Extract domain from current directory path (common in cPanel environments)
DOMAIN=$(basename "$PWD" 2>/dev/null)
if [ "$DOMAIN" = "public_html" ]; then
    # If we're in public_html, try to get domain from parent directory
    DOMAIN=$(basename "$(dirname "$PWD")" 2>/dev/null)
fi

# Try hostname as fallback if domain extraction failed
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "home" ]; then
    DOMAIN=$(hostname 2>/dev/null | sed 's/\./_/g')
fi

# Create output filename with domain and date in DDMMYY format
OUTPUT_FILE="${DOMAIN}_audit_$(date +%d%m%y_%H%M%S).txt"

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
        # Convert Windows line endings to Unix before saving
        LATEST_SCRIPT=$(echo "$LATEST_SCRIPT" | tr -d '\r')
        echo "$LATEST_SCRIPT" > "$0"
        chmod +x "$0"
        echo "Script updated to version $LATEST_VERSION. Restarting..."
        exec "$0" "$@"  # Restart the script with the same arguments
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
    grep -l "assert\|system\|passthru\|exec\|shell_exec" "$file" > /dev/null 2>&1 && suspicious=true
    
    if $suspicious; then
        return 0  # True in bash exit code terms
    else
        return 1  # False in bash exit code terms
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
    local max_plugins=25  # Maximum number of plugins to display detailed info for
    
    if [ ! -d "$plugins_dir" ]; then
        echo "No plugins directory found"
        return
    fi
    
    # Count total plugins
    local total_plugins=$(find "$plugins_dir" -maxdepth 1 -type d | wc -l)
    # Subtract 1 for the plugins directory itself
    total_plugins=$((total_plugins - 1))
    
    echo "List of installed plugins (total: $total_plugins, showing most recently modified):"
    
    # Get list of plugins sorted by last modification time (most recent first)
    find "$plugins_dir" -maxdepth 1 -type d -not -path "$plugins_dir" | while read plugin_dir; do
        last_modified=$(find "$plugin_dir" -type f -name "*.php" -exec stat -c "%Y %n" {} \; 2>/dev/null | sort -nr | head -1 | cut -d' ' -f1)
        if [ -z "$last_modified" ]; then
            last_modified=0
        fi
        echo "$last_modified $plugin_dir"
    done | sort -nr | head -$max_plugins | while read timestamp plugin; do
        plugin_dir=$(echo "$plugin" | cut -d' ' -f2-)
        plugin_name=$(basename "$plugin_dir")
        version="Unknown"
        
        # Try to get version from the main plugin file
        main_file="$plugin_dir/$plugin_name.php"
        if [ ! -f "$main_file" ]; then
            # Find the main plugin file
            main_file=$(grep -l "Plugin Name:" "$plugin_dir"/*.php 2>/dev/null | head -1)
        fi
        
        if [ -f "$main_file" ]; then
            version=$(grep "Version:" "$main_file" | head -1 | sed 's/.*Version: *\([^ ]*\).*/\1/')
            if [ -z "$version" ]; then
                version="Unknown"
            fi
        fi
        
        echo "  - $plugin_name (Version: $version)"
        
        # Get the last modified date of the plugin directory
        last_modified=$(find "$plugin_dir" -type f -name "*.php" -exec stat -c "%y" {} \; 2>/dev/null | sort -r | head -1)
        if [ ! -z "$last_modified" ]; then
            echo "    Last modified: $last_modified"
        fi
    done
    
    if [ "$total_plugins" -gt "$max_plugins" ]; then
        echo "  ... and $((total_plugins - max_plugins)) more plugins (output truncated)"
    fi
}

# Function to get theme information
get_themes_info() {
    local wp_dir="$1"
    local themes_dir="$wp_dir/wp-content/themes"
    local max_themes=10  # Maximum number of themes to display detailed info for
    
    if [ ! -d "$themes_dir" ]; then
        echo "No themes directory found"
        return
    fi
    
    # Count total themes
    local total_themes=$(find "$themes_dir" -maxdepth 1 -type d | wc -l)
    # Subtract 1 for the themes directory itself
    total_themes=$((total_themes - 1))
    
    echo "List of installed themes (total: $total_themes, showing most recently modified):"
    
    # Get list of themes sorted by last modification time (most recent first)
    find "$themes_dir" -maxdepth 1 -type d -not -path "$themes_dir" | while read theme_dir; do
        last_modified=$(find "$theme_dir" -type f -name "*.php" -exec stat -c "%Y %n" {} \; 2>/dev/null | sort -nr | head -1 | cut -d' ' -f1)
        if [ -z "$last_modified" ]; then
            last_modified=0
        fi
        echo "$last_modified $theme_dir"
    done | sort -nr | head -$max_themes | while read timestamp theme; do
        theme_dir=$(echo "$theme" | cut -d' ' -f2-)
        theme_name=$(basename "$theme_dir")
        version="Unknown"
        
        # Try to get version from the style.css file
        if [ -f "$theme_dir/style.css" ]; then
            version=$(grep "Version:" "$theme_dir/style.css" | head -1 | sed 's/.*Version: *\([^ ]*\).*/\1/')
            if [ -z "$version" ]; then
                version="Unknown"
            fi
        fi
        
        echo "  - $theme_name (Version: $version)"
        
        # Get the last modified date of the theme directory
        last_modified=$(find "$theme_dir" -type f -name "*.php" -exec stat -c "%y" {} \; 2>/dev/null | sort -r | head -1)
        if [ ! -z "$last_modified" ]; then
            echo "    Last modified: $last_modified"
        fi
    done
    
    if [ "$total_themes" -gt "$max_themes" ]; then
        echo "  ... and $((total_themes - max_themes)) more themes (output truncated)"
    fi
}

# Function to check for recently modified files
check_recent_files() {
    local wp_dir="$1"
    local days="$2"
    local max_files="$3"  # Maximum number of files to display
    local prev_dir=""     # Track previous directory for condensed output
    local count=0         # Counter for displayed files
    
    echo "Files modified in the last $days days (limited to $max_files entries):"
    
    # First, prioritize checking suspicious file extensions
    echo "  Checking for suspicious PHP files first..."
    find "$wp_dir" -type f -name "*.php" -mtime -"$days" 2>/dev/null | grep -v "wp-includes\|wp-admin\|languages" | sort -r | while read file; do
        # Only display suspicious PHP files
        is_suspicious=false
        check_suspicious_patterns "$file" > /dev/null && is_suspicious=true
        grep -q "eval\|base64\|create_function" "$file" 2>/dev/null && is_suspicious=true
        
        if $is_suspicious; then
            rel_path="${file#$wp_dir/}"
            echo "  - [SUSPICIOUS] $rel_path ($(stat -c "%y" "$file" 2>/dev/null))"
            ((count++))
        fi
        
        # Stop if we've reached the maximum
        if [ "$count" -ge "$max_files" ]; then
            echo "  ... and more (output truncated, increase max_files to see more)"
            return
        fi
    done
    
    # Then look for any non-core modified files
    find "$wp_dir" -type f -mtime -"$days" 2>/dev/null | grep -v "wp-includes\|wp-admin\|languages" | sort -r | while read file; do
        # Skip if we've reached the maximum
        if [ "$count" -ge "$max_files" ]; then
            echo "  ... and more (output truncated, increase max_files to see more)"
            return
        fi
        
        # Check if it's a core file
        is_core=false
        echo "$file" | grep -q "wp-includes\|wp-admin" && is_core=true
        
        # Only display interesting files (non-core or modified core files)
        if [ "$is_core" = false ]; then
            # Get current file directory
            current_dir=$(dirname "$file")
            
            # Get relative path (removes the WordPress root directory prefix)
            rel_path="${file#$wp_dir/}"
            
            # If same directory as previous file, just show filename
            if [ "$current_dir" = "$prev_dir" ]; then
                filename=$(basename "$file")
                echo "  - $filename ($(stat -c "%y" "$file" 2>/dev/null))"
            else
                # Show full relative path
                echo "  - $rel_path ($(stat -c "%y" "$file" 2>/dev/null))"
                prev_dir="$current_dir"
            fi
            
            ((count++))
        fi
    done
    
    if [ "$count" -eq 0 ]; then
        echo "  No significant modified files found in the given timeframe."
    fi
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

# Function to fix common security issues
fix_security_issues() {
    local wp_dir="$1"
    local issues_fixed=0
    
    echo "Fixing security issues:"
    
    # Fix wp-config.php permissions
    if [ -f "$wp_dir/wp-config.php" ]; then
        config_perms=$(stat -c "%a" "$wp_dir/wp-config.php" 2>/dev/null)
        if [ "$config_perms" == "777" ] || [ "$config_perms" == "666" ] || [ "$config_perms" == "644" ]; then
            echo "  - Fixing wp-config.php permissions from $config_perms to 640"
            chmod 640 "$wp_dir/wp-config.php" 2>/dev/null
            issues_fixed=$((issues_fixed+1))
        fi
    fi
    
    # Remove PHP files from uploads directory (potential malware)
    if [ -d "$wp_dir/wp-content/uploads" ]; then
        php_in_uploads=$(find "$wp_dir/wp-content/uploads" -name "*.php" -type f 2>/dev/null | wc -l)
        if [ "$php_in_uploads" -gt 0 ]; then
            echo "  - Found $php_in_uploads PHP files in uploads directory (potential malware)"
            echo "    These should be manually reviewed and removed if malicious"
            find "$wp_dir/wp-content/uploads" -name "*.php" -type f 2>/dev/null | head -5 | while read file; do
                echo "    - $file"
            done
            issues_fixed=$((issues_fixed+php_in_uploads))
        fi
    fi
    
    # Fix suspicious files with double extensions
    suspicious_files=$(find "$wp_dir" -type f -name "*.ico.php" -o -name "*.png.php" -o -name "*.jpg.php" -o -name "*shell*.php" 2>/dev/null | wc -l)
    if [ "$suspicious_files" -gt 0 ]; then
        echo "  - Found $suspicious_files suspiciously named files (potential backdoors)"
        echo "    These should be manually reviewed and removed if malicious"
        find "$wp_dir" -type f -name "*.ico.php" -o -name "*.png.php" -o -name "*.jpg.php" -o -name "*shell*.php" 2>/dev/null | head -5 | while read file; do
            echo "    - $file"
        done
        issues_fixed=$((issues_fixed+suspicious_files))
    fi
    
    if [ "$issues_fixed" -eq 0 ]; then
        echo "  - No issues fixed"
    else
        echo "  - Fixed $issues_fixed issues"
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
        
        # Fix security issues if --fix option is provided
        if [ "$FIX_ISSUES" = true ]; then
            fix_security_issues "$wp_dir"
            echo ""
        fi
        
        check_recent_files "$wp_dir" 7 50  # Limit to 50 most recent files
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
                
                # Fix security issues if --fix option is provided
                if [ "$FIX_ISSUES" = true ]; then
                    fix_security_issues "$wp_dir"
                    echo ""
                fi
                
                check_recent_files "$wp_dir" 7 50  # Limit to 50 most recent files
                echo ""
            fi
        done
        
        if [ "$found_wp" = false ]; then
            echo "No WordPress installations found in $current_dir or immediate subdirectories"
        fi
    fi
}

# Process command line arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        --update)
            FORCE_UPDATE=true
            ;;
        --fix)
            FIX_ISSUES=true
            echo "Fix mode enabled - will attempt to fix security issues"
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--update] [--fix]"
            exit 1
            ;;
    esac
    shift
done

# Always check for updates unless specifically running with --update flag
if [ "$FORCE_UPDATE" = true ]; then
    echo "Manual update check requested"
    update_script "$@"
    exit 0
else
    # Check for updates automatically but silently
    # Only show output if an update is available
    if command -v curl &> /dev/null; then
        LATEST_SCRIPT=$(curl -s "$GITHUB_URL")
    elif command -v wget &> /dev/null; then
        LATEST_SCRIPT=$(wget -q -O - "$GITHUB_URL")
    fi
    
    if [ ! -z "$LATEST_SCRIPT" ]; then
        LATEST_VERSION=$(echo "$LATEST_SCRIPT" | grep "SCRIPT_VERSION=" | head -1 | cut -d'"' -f2)
        
        if [ ! -z "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]; then
            echo "New version available: $LATEST_VERSION (current: $SCRIPT_VERSION)"
            echo "Updating script..."
            # Convert Windows line endings to Unix before saving
            LATEST_SCRIPT=$(echo "$LATEST_SCRIPT" | tr -d '\r')
            echo "$LATEST_SCRIPT" > "$0"
            chmod +x "$0"
            echo "Script updated to version $LATEST_VERSION. Restarting..."
            exec "$0" "$@"  # Restart the script with the same arguments
            exit 0
        fi
    fi
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