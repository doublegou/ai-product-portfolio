export function ContactFooter() {
  return <footer id="contact" className="contact-footer" tabIndex={-1} aria-labelledby="contact-heading">
    <div className="container contact-layout">
      <div className="contact-heading">
        <h2 id="contact-heading">联系我们</h2>
        <p>交流反馈、商务合作，欢迎联系。</p>
      </div>
        <section className="contact-qr" aria-labelledby="contact-wechat">
          <h3 id="contact-wechat">微信</h3>
          <img src="/contact/wechat.png" alt="微信联系二维码" width={707} height={670} loading="lazy" />
          <p>使用微信扫码添加</p>
        </section>
        <section className="contact-qr" aria-labelledby="contact-qq">
          <h3 id="contact-qq">QQ</h3>
          <img src="/contact/qq.png" alt="QQ 联系二维码" width={1012} height={1012} loading="lazy" />
          <p>使用 QQ 扫码添加</p>
        </section>
      <div className="contact-details">
        <section className="contact-direct" aria-labelledby="contact-email">
          <h3 id="contact-email">邮箱</h3>
          <a href="mailto:doublegou@gmail.com">doublegou@gmail.com</a>
        </section>
        <section className="contact-direct" aria-labelledby="contact-phone">
          <h3 id="contact-phone">电话</h3>
          <a href="tel:+8617810648168">+86 17810648168</a>
        </section>
      </div>
    </div>
  </footer>;
}
