document.documentElement.classList.add("js-enabled");

const revealItems = document.querySelectorAll(".reveal");

if ("IntersectionObserver" in window) {
  requestAnimationFrame(() => {
    revealItems.forEach((item) => {
      const rect = item.getBoundingClientRect();

      if (rect.top < window.innerHeight * 0.92) {
        item.classList.add("is-visible");
      }
    });
  });

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.18 }
  );

  revealItems.forEach((item) => observer.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}

const sections = [...document.querySelectorAll("main section[id]")];
const navLinks = [...document.querySelectorAll(".nav-links a")];

if ("IntersectionObserver" in window && sections.length > 0) {
  const navObserver = new IntersectionObserver(
    (entries) => {
      const visible = entries
        .filter((entry) => entry.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

      if (!visible) return;

      const activeLink = navLinks.find(
        (link) => link.getAttribute("href") === `#${visible.target.id}`
      );

      if (!activeLink) return;

      navLinks.forEach((link) => {
        link.classList.toggle("is-active", link === activeLink);
      });
    },
    {
      rootMargin: "-25% 0px -55% 0px",
      threshold: [0.12, 0.4, 0.7],
    }
  );

  sections.forEach((section) => navObserver.observe(section));
}
