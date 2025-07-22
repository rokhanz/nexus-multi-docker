# Nexus Multi-Node Manager

![Nexus Logo](https://img.shields.io/badge/NEXUS-Multi--Node--Manager-blue?style=for-the-badge&logo=docker&logoColor=white)

**🚀 Professional Multi-Node Management System 🚀**

*Simplified deployment and management for Nexus Network nodes*

![GitHub stars](https://img.shields.io/github/stars/rokhanz/nexus-multi-docker?style=flat)
![GitHub forks](https://img.shields.io/github/forks/rokhanz/nexus-multi-docker?style=flat)
![GitHub issues](https://img.shields.io/github/issues/rokhanz/nexus-multi-docker)
![Bash](https://img.shields.io/badge/Bash-4.0%2B-green)
![Docker](https://img.shields.io/badge/Docker-20.10%2B-blue)
---

## 🌟 Features

**Smart Node Management Features:**

🎯 **Smart Node Management** - Enhanced CRUD operations for node configuration

🔄 **Intelligent Allocation** - Gap-aware slot allocation system  

🛡️ **Enhanced Security** - Safe operations with multiple confirmations

🎨 **Visual Interface** - Color-coded displays for easy monitoring

📊 **Real-time Monitoring** - Live status tracking with detailed logs

🌐 **Proxy Support** - Advanced proxy rotation for IP diversification

🐳 **Docker Integration** - Automated container management

🔧 **Easy Configuration** - Intuitive setup and management interface

---

## 🚀 Quick Start

### 📋 Prerequisites

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **OS** | Linux | Ubuntu 20.04+ |
| **Memory** | 2GB RAM | 4GB+ RAM |
| **Disk** | 10GB free | 20GB+ SSD |
| **Network** | Stable Internet | High-speed Connection |

### ⚡ Installation

```bash
# Download and setup
wget https://raw.githubusercontent.com/rokhanz/nexus-multi/main/nexus-multi.sh
chmod +x nexus-multi.sh

# Run the manager
./nexus-multi.sh
```

---

## 🎮 Usage Guide

### 📱 Main Menu Interface

```
╔══════════════════════════════════════╗
║              MENU UTAMA              ║
╠══════════════════════════════════════╣
║  1. 🚀 Install Nexus                 ║
║  2. 📊 Status & Logs                 ║
║  3. ➕ Node Management               ║
║  4. 🗑️  Uninstall                    ║
║  5. 🚪 Exit                          ║
╚══════════════════════════════════════╝
```

### 🔧 Enhanced Node Management System

The script includes a comprehensive **Node ID management system** with full CRUD capabilities:

#### 🎯 Key Features:

| Feature | Description | Access |
|---------|-------------|--------|
| **Add Node** | Add new nodes to existing deployment | Menu 3 |
| **Edit Node** | Modify existing node configuration | Submenu 3.2 |
| **Delete Node** | Remove nodes from configuration | Submenu 3.3 |
| **Smart Allocation** | Automatic gap-filling allocation | Automatic |
| **Cancel Support** | Cancel anytime with 'cancel' | All inputs |
| **Navigation Flow** | Confirmation at every step | All operations |

#### 📝 Setup Process:

1. **Run Script**
   ```bash
   ./nexus-multi.sh
   ```

2. **Choose Installation or Management**
   - Install: Complete initial setup
   - Node Management: Add to existing deployment

3. **Enhanced Input System**
   ```
   Enter WALLET_ADDRESS (0x... or 'cancel' to abort): 0x...
   ✅ Valid wallet address format
   
   Continue with node addition process? (y/n): y
   ```

4. **Smart Node Configuration**
   ```
   Enter NODE_ID for Node 1 (or 'cancel' to abort): [numeric_id]
   ✅ Valid NODE_ID - will be verified by server
   
   Continue configuring Node 2? (y/n/q to quit): y
   ```

---

## 🔒 Security & Best Practices

### 🛡️ Security Considerations

| Nodes | Risk Level | Recommendation |
|-------|------------|----------------|
| 1-2 | 🟢 **Low Risk** | Similar to regular users |
| 3-5 | 🟡 **Medium Risk** | Balance efficiency and security |
| 6+ | 🔴 **High Risk** | Requires quality proxy setup |

### 📝 Best Practices

1. **Always use proxy** for IP diversification
2. **Monitor logs regularly** to ensure nodes run properly
3. **Use separate configurations** when possible
4. **Regular backup** of environment configuration
5. **Gradual scaling** to avoid detection

---

## 🌐 Proxy Configuration

### Supported Formats

| Type | Format Example | Notes |
|------|----------------|-------|
| Basic HTTP | `http://proxy.example.com:[port]` | Standard HTTP proxy |
| HTTP with Auth | `http://user:pass@proxy.example.com:[port]` | With authentication |
| HTTPS | `https://secure.proxy.example.com:[port]` | Secure HTTPS proxy |

### Setup Instructions

1. **Create proxy configuration file:**
   ```bash
   nano ~/nexus-multi-docker/proxy_list.txt
   ```

2. **Add proxies (one per line):**
   ```
   http://proxy1.example.com:[port]
   http://user:pass@proxy2.example.com:[port]
   https://secure.proxy.example.com:[port]
   ```

3. **Automatic rotation applied per node**

---

## 📁 File Structure

```bash
~/nexus-multi-docker/                    # Working directory
├── .env                                 # Environment variables
├── proxy_list.txt                       # Proxy configuration
├── docker-compose.yml                   # Multi-node compose file
└── .env.backup                          # Auto-backup configuration

~/.nexus/                                # Nexus runtime directory
├── config.json                          # Main configuration
├── node1/                               # Node 1 specific config
├── node2/                               # Node 2 specific config
└── ...                                  # Additional nodes
```

### Configuration Structure

```bash
# Environment file example
WALLET_ADDRESS=0x...                     # Shared wallet for all nodes
NODE_COUNT=3                             # Total active nodes
NODE_ID_1=...                            # Node 1 individual ID
NODE_ID_2=...                            # Node 2 individual ID
NODE_ID_3=...                            # Node 3 individual ID
DEBUG=false                              # Debug mode flag
```

---

## 🛠️ Troubleshooting

### Common Issues

#### Docker Permission Issues
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Logout and login again
```

#### Resource Conflicts
```bash
# Check system resources
free -h
df -h

# Clean Docker resources
docker system prune -f
```

#### Container Issues
```bash
# Check Docker daemon
sudo systemctl status docker
sudo systemctl start docker

# Check container status
docker ps -a --filter "name=nexus-node-"
```

### 🔍 Advanced Debugging

#### System Health Check
```bash
# Monitor resource usage
htop

# Docker resource monitoring
docker stats

# Check disk usage
du -sh ~/nexus-multi-docker/*
```

#### Log Analysis
```bash
# Individual node logs
docker logs [container_name]

# System logs
journalctl -u docker.service
```

---

## ❓ FAQ

### General Questions

**Q: What's the maximum number of nodes supported?**
A: The script supports up to 10 nodes. For more than 10 nodes, script modification is required.

**Q: Is proxy usage mandatory?**
A: Not mandatory, but highly recommended for IP diversification and reduced detection risk.

**Q: Is it safe to run this on a VPS with other applications?**
A: Yes! The script only manages containers with the `nexus-node-*` prefix and won't interfere with other Docker containers.

### Node Management

**Q: How do I add new nodes to an existing deployment?**
A: Use Menu 3 (Node Management) → Option 1 (Add Node). The system will automatically find and fill empty slots.

**Q: Can I modify existing node configurations?**
A: Yes, use Menu 3 → Option 2 (Edit Node) to modify existing node settings with full validation.

**Q: How does the gap-aware allocation work?**
A: The system automatically fills empty slots first instead of appending to the end, ensuring efficient resource utilization.

---

## 🔧 Advanced Features

### Enhanced Navigation System

- **✅ Cancel Anywhere**: Type 'cancel' in any input field
- **✅ Y/N Confirmations**: Confirmation at every critical step
- **✅ Smart Retry**: "Press Enter to retry or 'cancel' to return"
- **✅ Multiple Exit Points**: Various options to return to menu
- **✅ Progress Tracking**: Clear status at every stage

### Smart Container Management

The script uses strict filtering to ensure safety:
- Only manages containers with `nexus-node-*` naming pattern
- Preserves all other Docker containers and images
- Safe uninstall that won't affect other applications
- Automatic cleanup with rollback capabilities

---

## 📈 Performance Tips

1. **Optimal Node Count**: 3-5 nodes for standard VPS
2. **Memory Requirements**: Minimum 2GB RAM for 3 nodes
3. **Storage**: 20GB+ free space recommended
4. **Network**: Stable connection with adequate bandwidth
5. **Proxy Quality**: Use residential proxies for best results

---

## 👨‍💻 Author & Support

**ROKHANZ**
- GitHub: [@rokhanz](https://github.com/rokhanz)
- Project: [nexus-multi](https://github.com/rokhanz/nexus-multi)

### Getting Help

- **GitHub Issues**: [Report bugs or request features](https://github.com/rokhanz/nexus-multi-docker/issues)
- **Documentation**: Read this README thoroughly
- **Community**: Join discussions on GitHub

---

## 📄 License

This project is licensed under the MIT License.

---

## 🌟 Enhanced Version Features

**🎛️ Complete CRUD Management • 🧠 Smart Allocation • 🛡️ Enhanced Safety**

**🔄 Flexible Navigation • 🎨 Visual Management • 🔒 Safe Operations**

---

### ⭐ Star this Repository

If this script helped you, don't forget to give it a ⭐ on GitHub!

**[⭐ Star on GitHub](https://github.com/rokhanz/nexus-multi-docker)**

---

**© 2025 Nexus Multi-Node Manager** | Made with ❤️ by ROKHANZ

**Happy node running! 🚀**
