# 一键安装
在安装前请确保你的系统支持`bash`环境,且系统网络正常  


# 配置要求  
## 内存  
- 128MB minimal/256MB+ recommend  
## OS  
- Ubuntu 22-24

-FinalShell下载地址 [FinalShell](https://dl.hostbuf.com/finalshell3/finalshell_windows_x64.exe)

# VLESS+Reality+uTLS+Vision+Xray-core协议
```
bash <(curl -Ls https://raw.githubusercontent.com/Firefly-xui/vless/master/VLESS+Reality+uTLS+Vision+Xray-core.sh)
```  


抗识别性极强：Reality 模拟浏览器握手，借助 uTLS 和 Vision，将流量伪装为正常 TLS；

无需证书：相比传统 TLS，Reality 不依赖于域名/签发证书，部署更灵活；

低识别风险：支持伪装为真实站点（如 Cloudflare、NVIDIA），对防火墙极度友好；

基于 TCP：流量更稳定，尤其适合城市宽带 / 教育网；

无需中间代理：直接入口部署即可使用。

适用场景：

长期开通的公网节点；

高干扰 / 高频封锁区域；

注重隐蔽性和可信度



| 协议组合                            | 抗封锁   | 延迟    | 稳定性   | 部署复杂度 | 适用建议       |
| ------------------------------- | ----- | ----- | ----- | ----- | ---------- |
| Hysteria2 + UDP + TLS + Obfs    | ★★★☆☆ | ★★★★★ | ★★★☆☆ | ★★☆☆☆ | 流媒体 / 备用   |
| TUIC + UDP + QUIC + TLS         | ★★★★☆ | ★★★★★ | ★★★★☆ | ★★★★★ | 游戏 / 多任务场景 |
| VLESS + Reality + uTLS + Vision | ★★★★★ | ★★★☆☆ | ★★★★☆ | ★☆☆☆☆ | 配置简单安全可靠       |

