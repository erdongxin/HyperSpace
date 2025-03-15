# 需要手动执行命令，把密钥存到服务器中
echo -e "3aekksL*************p2UGSwZ5ND" > /root/my.pem && chmod 600 /root/my.pem

# 使用screen启动
curl -O https://raw.githubusercontent.com/erdongxin/HyperSpace/refs/heads/main/hyper_start.sh && chmod +x hyper_start.sh && screen -dmS hyper bash -c "./hyper_start.sh"

# 脚本说明
1、无限启动至成功为止
2、每5分钟检测一次错误，报错则自动重启
3、超过两小时分数不增加，自动重启
4、查看日志 screen -r hyper，按Ctrl + A + D 安全退出

