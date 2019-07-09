rm -rf public
git add .
git commit -m add
git push
hugo
cp -r public/* ~/work/src/github.com/sealyun/sealyun.github.io 
cd ~/work/src/github.com/sealyun/sealyun.github.io
git add .
git commit -m add
git push
