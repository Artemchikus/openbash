Для создания одноузлового кластера надо:

1. Открыть Linux
2. dnf -y install qemu-kvm libvirt virt-install - установить пакеты для KVM
3. Скачать архив с дисками и конфигами узла по ссылке https://drive.google.com/file/d/1R2It8H-8W-f6NFA58IKU9FDxS2DGcu0Q/view?usp=sharing 
4. Разархивировать архив
5. sudo cp *qcow2 /mnt/kvm/disk - перенести файлы дсиков в нужную папку
6. sudo virsh net-define default.xml - создать сеть для узла
7. sudo net-autostart default - настроить автозапуск сети
8. sudo virsh define cont9.xml - создать определеие ВМ
9.  sudo virsh start cont9 - запустить ВМ
10. sudo virsh console cont9 - закрепить консоль ВМ за терминалом
11. export ИМЯ_ПЕРЕМЕННОЙ=ЗНАЧЕНИЕ - адать ENV переменные для конфигруации (опционально)
12. ./configure.sh - запустить скрипт конфигурации сервисов Openstack
13. source keystonerc_adm - запсутить скрипт для работы с Openstack через командную строку
14. Ctrl + [] - открепить консоль
15. sudo virsh shutdown cont9 - выключить ВМ
