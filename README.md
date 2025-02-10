手动执行命令，把密钥存到服务器中
echo -e "3aekksL*************p2UGSwZ5ND" > /root/my.pem && chmod 600 /root/my.pem

使用screen启动
curl -O https://raw.githubusercontent.com/erdongxin/HyperSpace/refs/heads/main/hyper_start.sh && chmod +x hyper_start.sh && screen -dmS hyper bash -c "./hyper_start.sh"

查看日志 screen -r hyper，按Ctrl + A + D 安全退出

