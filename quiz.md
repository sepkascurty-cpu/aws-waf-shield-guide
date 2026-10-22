# AWS WAF & Shield — Quiz

Test yourself. Answers are collapsed — no peeking. 👀

---

### 1. In what order does a WAF Web ACL evaluate its rules, and why does it matter?

<details>
<summary>Answer</summary>

Rules are evaluated in **priority order (lowest number first)**. Order matters
because the **first rule whose action is terminal** (Allow/Block, not Count)
decides the request's fate — a broad Block rule placed above a narrow Allow
rule will block traffic you meant to permit.
</details>

---

### 2. Your new custom rule is blocking real users. What action should you have used first, and what does it do?

<details>
<summary>Answer</summary>

**Count.** It logs every request that *would* have matched without actually
blocking it — a dry-run mode. Deploy new rules in Count, watch the logs for
false positives, then flip to Block or CAPTCHA.
</details>

---

### 3. What's the difference between AWS Shield Standard and Shield Advanced?

<details>
<summary>Answer</summary>

**Shield Standard** is free and always on: it protects against common L3/L4 DDoS
attacks (SYN floods, UDP reflection) for all AWS resources. **Shield Advanced**
(~$3,000/month) adds protection against larger, sophisticated attacks, 24/7
access to the DDoS Response Team (DRT), advanced attack diagnostics, and
**cost protection** against scaling charges caused by the attack.
</details>

---

### 4. Where in the stack does WAF inspect traffic, and what does that buy you?

<details>
<summary>Answer</summary>

At the **edge** (CloudFront, ALB, API Gateway, AppSync, Cognito — wherever you
associate the Web ACL). Malicious requests are dropped **before** they reach
your origin, so your servers never spend CPU on attacks, and you don't pay
for the compute that would have served them.
</details>

---

### 5. A scraper is hammering your login endpoint from rotating IPs, ~200 req/min per IP. Which WAF feature stops it, and which action avoids punishing real users?

<details>
<summary>Answer</summary>

A **rate-based rule** (e.g., limit 100 requests per 5 minutes per IP) stops the
hammering. Use the **CAPTCHA** or **Challenge** action instead of Block: bots
fail the silent check while real users pass through unbothered.
</details>
