#!/build/bin/busybox/sh

BSDIR=/work
WORK=/work/.init
INITCONF=/.init/init.conf
DATE=`date +"%Y-%m-%d %R:%S"`

mkdir -p /.init/services /tmp
mkdir -p $WORK

if [ ! -d $WORK ]; then
    echo "[$DATE] Can not create work dir.."
    exit 0
fi

if [ -f $WORK/init.conf ]; then
   INITCONF=$WORK/init.conf
fi

if [ -d /build/services ]; then      
   cp -a /build/services/* /.init/services
fi

if [ -d $WORK/services ]; then      
   cp -a $WORK/services/* /.init/services
fi

if [ -f $WORK/init.sh ]; then
    sh $WORK/init.sh
fi
echo "start supervisord"
exec tini -s -- /build/bin/supervisord -c $INITCONF
