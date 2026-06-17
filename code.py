import pyotp
   
   # 填入你截图中的密钥，去空格
totp = pyotp.TOTP("fhhui5tlkhki6mz6ytr5bq3g3fdz23fv")
print("当前的6位验证码是:", totp.now())