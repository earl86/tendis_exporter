package collector

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// ==============================================================================
// TendisInstance 封装结构体
// 对应 mysqld_exporter 中的 instance struct
// ==============================================================================
type TendisInstance struct {
	Client *redis.Client
	Name   string // 实例标识 (通常是 ip:port)
}

// ==============================================================================
// 工厂方法：创建一个新的 Tendis 连接实例
// ==============================================================================
func NewTendisInstance(ctx context.Context, addr string, password string) (*TendisInstance, error) {
	// 1. 配置 Tendis 选项
	// 这里设置了较短的超时时间，因为 Exporter 采集不应该阻塞太久
	opts := &redis.Options{
		Addr:     addr,     // "localhost:6379"
		Password: password, // "" if no password
		DB:       0,        // 默认连接 DB 0，INFO 命令是全局的，跟 DB 无关

		// 关键：超时设置 (防止网络卡顿时 Exporter 挂死)
		DialTimeout:  5 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,

		// 连接池配置 (对于单次采集，其实不需要太大的池子，但保持默认即可)
		PoolSize:     2,
		MinIdleConns: 1,
	}

	// 2. 创建客户端 (此时还没有真正发起网络连接)
	rdb := redis.NewClient(opts)

	// 3. 立即执行一次 PING，确保连接是通的 (Fail Fast 原则)
	// 如果连不上，直接报错，不要等到 Scrape 的时候才报错
	if err := rdb.Ping(ctx).Err(); err != nil {
		// 记得关闭，防止资源泄漏
		_ = rdb.Close()
		return nil, fmt.Errorf("failed to connect to Tendis at %s: %w", addr, err)
	}

	// 4. 返回实例
	return &TendisInstance{
		Client: rdb,
		Name:   addr,
	}, nil
}

// ==============================================================================
// 资源释放方法
// ==============================================================================
func (r *TendisInstance) Close() error {
	if r.Client != nil {
		return r.Client.Close()
	}
	return nil
}

// String 方法用于日志打印，方便调试
func (r *TendisInstance) String() string {
	return r.Name
}
