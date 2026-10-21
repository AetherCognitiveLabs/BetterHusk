#pragma once
typedef int mach_port_t; typedef unsigned int mach_msg_type_number_t;
typedef int kern_return_t; typedef long long mach_vm_address_t; typedef unsigned long long mach_vm_size_t;
#define KERN_SUCCESS 0
int task_info(mach_port_t, int, void *, mach_msg_type_number_t *);
