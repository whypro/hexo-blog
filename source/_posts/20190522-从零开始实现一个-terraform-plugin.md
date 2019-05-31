---
title: 从零开始实现一个 terraform plugin
tags:
  - 原创
  - terraform
  - Golang
categories: []
toc: true
date: 2019-05-22 14:13:02
---

terraform 作为一个优秀的开源基础设施管理、构建工具，官方或第三方提供了很多 plugin 来对接各种云平台（IaaS）。然而在我们平时开发和测试过程中，需要使用内部的 IaaS 服务频繁创建和删除 VM，而目前人工操作的方式比较费时费力，且没有现成的 plugin 可以使用。为了更方便地利用 terraform 工具来对内部 IaaS 资源进行管理和操作，我们决定自己开发一个 terraform plugin。

<!-- more -->

## 定义 Provider Schema

首先，我们定义入口文件 `main.go`：

``` golang
package main

import (
    "github.com/hashicorp/terraform/plugin"
    qvm "qiniu.com/kirk-deploy/pkg/qvm/terraform"
)

func main() {
    plugin.Serve(&plugin.ServeOpts{
        ProviderFunc: qvm.Provider,
    })
}
```

其中 `qvm.Provider` 函数负责创建一个 provider resource。

``` golang
func Provider() terraform.ResourceProvider {
    return &schema.Provider{
        Schema: map[string]*schema.Schema{
            "url": {
                Type:        schema.TypeString,
                Optional:    true,
                DefaultFunc: schema.EnvDefaultFunc("QVM_URL", ""),
                Description: descriptions["url"],
            },
            "ak": {
                Type:        schema.TypeString,
                Optional:    true,
                DefaultFunc: schema.EnvDefaultFunc("QVM_AK", ""),
                Description: descriptions["ak"],
            },
            "sk": {
                Type:        schema.TypeString,
                Optional:    true,
                DefaultFunc: schema.EnvDefaultFunc("QVM_SK", ""),
                Description: descriptions["sk"],
            },
        },
        ResourcesMap: map[string]*schema.Resource{
            "compute_instance": resourceComputeInstance(),
        },
        ConfigureFunc: configureProvider,
    }
}
```

`Schema` 声明了 provider 配置文件的定义，对应的 `tf` 文件这样写：

``` terraform
provider qvm {
    url = "https://qvm.qiniuapi.com"
    ak = "your app key"
    sk = "your app secret"
}
```

如果不在 `tf` 文件里指定 `ak` 和 `sk`，则 terraform 会根据 `DefaultFunc`，从环境变量 `QVM_AK` 和 `QVM_SK` 中获取。`Optional` 代表字段是可选的，即使用户没有填也不会报错。

`ResourcesMap` 声明了 provider 支持的资源和对应资源的工厂函数，例如这里我们只实现了计算资源，工厂函数的定义我们稍后再解释。

## 定义 Resource Schema

上面提到的 `resourceComputeInstance` 负责创建一个 compute instance resource，对于计算资源我们可以这样定义：

``` golang
func resourceComputeInstance() *schema.Resource {
    return &schema.Resource{
        Create: resourceComputeInstanceCreate,
        Read:   resourceComputeInstanceRead,
        Update: resourceComputeInstanceUpdate,
        Delete: resourceComputeInstanceDelete,
        Timeouts: &schema.ResourceTimeout{
            Create: schema.DefaultTimeout(30 * time.Minute),
            Update: schema.DefaultTimeout(30 * time.Minute),
            Delete: schema.DefaultTimeout(30 * time.Minute),
        },
        Schema: map[string]*schema.Schema{
            "image_id": {
                Type:     schema.TypeString,
                Optional: true,
                ForceNew: true,
            },
            "instance_name": {
                Type:     schema.TypeString,
                Optional: true,
            },
            "system_disk": {
                Type:     schema.TypeList,
                Required: true,
                MaxItems: 1,
                Elem: &schema.Resource{
                    Schema: map[string]*schema.Schema{
                        "category": {
                            Type:     schema.TypeString,
                            Optional: true,
                            Default:  enums.DiskCategoryCloudEfficiency,
                            ForceNew: true,
                        },
                        "size": {
                            Type:     schema.TypeInt,
                            Optional: true,
                            Default:  40,
                        },
                    },
                },
            },
            "data_disk": {
                Type:     schema.TypeList,
                Optional: true,
                MinItems: 1,
                MaxItems: 15,
                Elem: &schema.Resource{
                    Schema: map[string]*schema.Schema{
                        "category": {
                            Type:     schema.TypeString,
                            Optional: true,
                            Default:  enums.DiskCategoryCloudEfficiency,
                            ForceNew: true,
                        },
                        "size": {
                            Type:     schema.TypeInt,
                            Optional: true,
                            Default:  40,
                        },
                    },
                },
            },
        },
    }
}
```

`Create` `Read` `Update` `Delete` 分别是管理资源的回调函数，terraform 框架会在合适的时间调用这几个函数，`Timeouts` 定义了每个操作的超时时间，`Schema` 与上面一样，是定义 `tf` 文件的具体结构。

`ForceNew` 代表一旦这个字段改变，则 terraform 会删除并重新创建该资源。`TypeList` 定义了一个列表，如果 `MaxItems: 1` 时，列表退化为单个资源。

为了简化起见，`Schema` 我们省略了很多字段，对应的 `tf` 文件可以这样写：

``` terraform
resource "compute_instance" "test" {
    count = "${var.count}"
    provider = "qvm"
    image_id = "${var.image}"
    instance_name = "${var.instance_name}-${count.index}"
    system_disk {
        category = "efficiency"
        size = 40
    }
}
```

其中 `${var.}` 代表在 varaibles.tf 文件里定义的变量，具体可以用法可以参考 terraform 官方文档，这里不过多地介绍。

## 定义 Resource Operation Function

### Create


``` golang
func resourceComputeInstanceCreate(d *schema.ResourceData, meta interface{}) error {
    config := meta.(*Config)
    client, err := config.computeClient()
    if err != nil {
        return err
    }

    systemDisk := d.Get("system_disk").([]interface{})[0].(map[string]interface{})

    systemDiskParameters := params.CreateInstanceSystemDiskParameters{
        Category: enums.DiskCategory(systemDisk["category"].(string)),
        Size:     systemDisk["size"].(int),
    }

    parameters := &params.CreateInstanceParameters{
        ImageId:            d.Get("image_id").(string),
        SystemDisk:         systemDiskParameters,
        InstanceName:       enums.InstanceName(d.Get("instance_name").(string)),
    }

    log.Printf("[DEBUG] CreateInstanceParameters: %#v", parameters)
    rsp, err := client.CreateInstance(parameters)
    if err != nil {
        log.Printf("[ERROR] create instance error, %v", err)
        return err
    }
    log.Printf("[INFO] Instance ID: %s", rsp.Data.InstanceId)
    d.SetId(rsp.Data.InstanceId)

    return resourceComputeInstanceRead(d, meta)
}
```

`Create` 的实现最重要的一个操作是 `SetId`，如果服务端资源创建成功，会返回一个 InstanceId，`SetId` 会将这个 InstanceId 保存，作为以后判断资源是否更新的 key。

return 前又进行了一次 `Read` 操作，是为了防止有些状态字段没有通过 CreateResponse 返回，再尝试通过一次 Read 来获取这些状态信息。

### Delete

``` golang
func resourceComputeInstanceDelete(d *schema.ResourceData, meta interface{}) error {
    config := meta.(*Config)
    client, err := config.computeClient()
    if err != nil {
        return err
    }

    p := &params.DeleteInstanceParameters{
        InstanceId: d.Id(),
    }

    _, err = client.DeleteInstance(p)
    if err != nil {
        return err
    }

    return nil
}
```

### Update

``` golang
func resourceComputeInstanceUpdate(d *schema.ResourceData, meta interface{}) error {
    return resourceComputeInstanceRead(d, meta)
}
```

我们暂时不实现 `Update` 操作，因此这里只是简单地返回 Read。

### Read

``` golang
func resourceComputeInstanceRead(d *schema.ResourceData, meta interface{}) error {
    config := meta.(*Config)
    client, err := config.computeClient()
    if err != nil {
        return err
    }

    p := &params.DescribeInstanceParameters{
        InstanceId: d.Id(),
    }

    rsp, err := client.GetInstance(p)
    if err != nil {
        return err
    }

    instance := &rsp.Data
    d.Set("image_id", instance.ImageId)
    d.Set("instance_name", instance.InstanceName)
    // ...

    return nil
}
```

`Read` 通过 InstanceId 对资源状态进行查询，保存至 resource data。

## 编译和构建

上面基本代码框架实现后，我们就可以对 plugin 进行编译和构建了：

``` sh
go build -o terraform-provider-qvm
```

二进制文件的命名必须遵守以下命名规则：

```
terraform-provider-<NAME>
```

构建后，我们手动将二进制拷贝至 terraform 默认的插件目录：`${HOME}/.terraform/plguins`。


## 使用

进入工作目录，即 `tf` 文件保存的目录，假设这个目录的结构为：

```
terraform/qvm
├── provider.tf
├── resources.tf
├── variables.tf
└── terraform.tfvars
```

### 初始化

```
terraform init
```

### 修改配置

可以通过 `export` 或创建 `.tfvars` 文件，对配置进行修改：

```
export QVM_AK=
export QVM_SK=
```

创建 `terraform.tfvars` 文件：

```
instance_name = ""
count = 1
image = ""
```

### 查看更改

```
terraform plan
```

执行后 terraform 会对配置进行合法性校验。

### 应用更改

```
terraform apply
```

或者指定 `.tfvars` 文件：

```
terraform apply -var-file="terraform.tfvars"
```

### 销毁

```
terraform destroy
```

或者指定 `.tfvars` 文件：

```
terraform destroy -var-file="terraform.tfvars"
```

## 参考

https://www.terraform.io/docs/extend/writing-custom-providers.html

https://www.terraform.io/docs/extend/how-terraform-works.html