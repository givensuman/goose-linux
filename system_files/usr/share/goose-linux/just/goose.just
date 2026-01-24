# Display help with common tasks
goose-help:
    #!/usr/bin/env bash
    cat << 'EOF'
    🪿 goose-linux Quick Reference
    
    Getting Started:
    - First-time setup:        ujust goose-setup-firstboot
    - Update everything:       ujust goose-update
    - System status:           ujust goose-status
    
    System Management:
    - Clean up system:         ujust goose-clean
    - Backup configs:          ujust goose-backup-configs
    - Restore configs:         ujust goose-restore-configs <path>
    
    Development:
    - Enter dev container:     ujust goose-enter-toolbox [name]
    - Build toolboxes:         ujust goose-build-toolboxes
    - Export toolbox:          ujust goose-export-toolbox <name> [path]
    
    Package Management:
    - Layer package:           rpm-ostree install <package>
    - List layered packages:   rpm-ostree status
    - Install flatpak:         flatpak install <app>
    - Install CLI tool:        brew install <tool>
    
    Troubleshooting:
    - Rollback changes:        rpm-ostree rollback
    - Check logs:              journalctl -b
    - Reset flatpak:           flatpak repair
    
    Documentation: https://github.com/givensuman/goose-linux
    Issues: https://github.com/givensuman/goose-linux/issues
    EOF

# First-boot interactive setup
goose-setup-firstboot:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "🪿 Welcome to goose-linux!"
    echo ""
    echo "Let's get you set up with some common configurations..."
    echo ""
    
    # Install recommended shell
    read -p "Install Fish shell? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing Fish shell..."
        rpm-ostree install --apply-live fish
        sudo usermod -s $(which fish) $USER
        echo "✓ Fish installed. Log out and back in to use it."
    fi
    
    # Set up Docker
    read -p "Enable rootless Docker? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Configuring Docker..."
        sudo groupadd docker 2>/dev/null || true
        sudo usermod -aG docker $USER
        echo "✓ Docker configured. Log out and back in for it to take effect."
    fi
    
    # Create default toolbox
    read -p "Create default development toolbox? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Creating toolbox..."
        distrobox create
        echo "✓ Toolbox created. Enter with: distrobox enter"
    fi
    
    # Install common CLI tools
    read -p "Install recommended CLI tools with Homebrew? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing CLI tools..."
        brew install bat eza fd ripgrep zoxide
        echo "✓ CLI tools installed (bat, eza, fd, ripgrep, zoxide)"
    fi
    
    echo ""
    echo "🎉 Setup complete!"
    echo "Run 'ujust goose-help' anytime for quick reference."

# Update everything (rpm-ostree, flatpaks, brew)
goose-update:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "🔄 Updating goose-linux..."
    echo ""
    
    echo "📦 Updating system packages..."
    rpm-ostree update
    
    echo ""
    echo "📦 Updating flatpaks..."
    flatpak update -y
    
    echo ""
    echo "🍺 Updating Homebrew..."
    brew update && brew upgrade
    
    echo ""
    echo "🐳 Updating container images..."
    podman auto-update || true
    
    echo ""
    echo "✅ All updates complete!"
    echo "Reboot to apply system updates: systemctl reboot"

# Show system status and health
goose-status:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "🪿 goose-linux System Status"
    echo "=============================="
    echo ""
    echo "📦 System Version:"
    rpm-ostree status | head -n 20
    echo ""
    echo "🐳 Container Services:"
    systemctl --user is-active podman.socket docker.socket 2>/dev/null || echo "  Not running"
    echo ""
    echo "📦 Flatpak Updates Available:"
    flatpak remote-ls --updates --columns=application 2>/dev/null | wc -l | xargs echo "  "
    echo ""
    echo "💾 Disk Usage:"
    df -h / | tail -1 | awk '{print "  Root: " $3 " used of " $2 " (" $5 ")"}'
    echo ""
    echo "🧊 Memory:"
    free -h | grep Mem | awk '{print "  " $3 " used of " $2}'
    echo ""
    echo "🏃 Uptime:"
    uptime -p | sed 's/up /  /'

# Clean up old packages and Docker/Podman images and volumes
goose-clean:
    #!/usr/bin/env bash
    set -euox pipefail

    echo "🧹 Cleaning up system..."
    echo ""
    
    echo "Cleaning Docker..."
    docker system prune -af || true
    sudo docker system prune -af || true
    
    echo ""
    echo "Cleaning Podman..."
    podman system prune -af || true
    sudo podman system prune -af || true
    
    echo ""
    echo "Removing unused flatpaks..."
    flatpak uninstall --unused -y
    
    echo ""
    echo "Cleaning rpm-ostree..."
    rpm-ostree cleanup -bm
    
    echo ""
    echo "Cleaning Homebrew..."
    brew cleanup || true
    
    echo ""
    echo "✅ Cleanup complete!"

# Build various Distrobox toolboxes with pre-defined volumes
goose-build-toolboxes:
    #!/usr/bin/env bash
    set -euox pipefail

    toolbox_names=$(grep '^\[' /usr/share/distrobox/distrobox.ini | sed 's/^\[\(.*\)\]$/\1/' | tr '\n' ' ' | sed 's/ $//')
    toolbox_regex=$(echo "$toolbox_names" | tr ' ' '|')

    echo "Checking for existing toolboxes..."
    existing_toolboxes=$(distrobox list --format json | jq -r '.[] | select(.Name | test("'$toolbox_regex'")) | .Name' | tr '\n' ' ' || true)

    replace=false
    if [ -n "$existing_toolboxes" ]; then
        echo "Existing toolboxes found: $existing_toolboxes"
        read -p "Replace existing toolboxes? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            replace=true
        fi
    fi

    if [ "$replace" = true ]; then
        echo "Stopping existing toolboxes..."
        distrobox stop $toolbox_names || true

        echo "Building toolboxes with replacement..."
        distrobox assemble create --replace --file /usr/share/distrobox/distrobox.ini
    else
        echo "Building toolboxes..."
        distrobox assemble create --file /usr/share/distrobox/distrobox.ini
    fi

# Enter a specific toolbox
goose-enter-toolbox name='fedora-toolbox':
    #!/usr/bin/env bash
    set -euox pipefail

    echo "Entering toolbox {{ name }}..."
    distrobox enter {{ name }}

# Backup user configurations
goose-backup-configs location="$HOME/goose-backup-$(date +%Y%m%d)":
    #!/usr/bin/env bash
    set -euo pipefail
    
    mkdir -p "{{ location }}"
    
    echo "📦 Backing up to {{ location }}"
    
    # Backup important configs
    [ -d "$HOME/.config" ] && cp -r "$HOME/.config" "{{ location }}/" || true
    [ -d "$HOME/.local/share" ] && cp -r "$HOME/.local/share" "{{ location }}/" || true
    
    # List installed flatpaks
    flatpak list --app --columns=application > "{{ location }}/flatpak-apps.txt"
    
    # List layered packages
    rpm-ostree status --json | jq -r '.deployments[0].packages[]' > "{{ location }}/layered-packages.txt" 2>/dev/null || true
    
    # List brew packages
    brew list > "{{ location }}/brew-packages.txt" 2>/dev/null || true
    
    # Distrobox list
    distrobox list > "{{ location }}/distrobox-containers.txt" 2>/dev/null || true
    
    echo "✅ Backup complete: {{ location }}"

# Restore user configurations
goose-restore-configs location:
    #!/usr/bin/env bash
    set -euo pipefail
    
    if [ ! -d "{{ location }}" ]; then
        echo "❌ Backup location not found: {{ location }}"
        exit 1
    fi
    
    echo "⚠️  This will overwrite existing configurations!"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Restore configs
    [ -d "{{ location }}/.config" ] && cp -r "{{ location }}/.config" "$HOME/" || true
    [ -d "{{ location }}/.local/share" ] && cp -r "{{ location }}/.local/share" "$HOME/" || true
    
    echo "✅ Restore complete. Some changes may require logout."

# Export toolbox as tar archive
goose-export-toolbox name location="$HOME":
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "📦 Exporting toolbox: {{ name }}"
    output_file="{{ location }}/{{ name }}-$(date +%Y%m%d).tar.gz"
    
    # Get container ID
    container_id=$(podman ps -a --filter "name={{ name }}" --format "{{{{.ID}}}}" | head -1)
    
    if [ -z "$container_id" ]; then
        echo "❌ Toolbox {{ name }} not found"
        exit 1
    fi
    
    # Export container
    podman export "$container_id" | gzip > "$output_file"
    
    echo "✅ Exported to $output_file"
