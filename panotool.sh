#!/bin/sh
set -e

function cyl2rect()
{
    echo "TODO XXX"
    exit 1
}

function cyl2eqr() 
{
    if [ $# -lt 3 ]; then
        echo "not enough args for cyl2eqr"
        echo "cyl2eqr <HFOV> <inputTif> <outputTiff> [nona options]"
        exit 1
    fi
    HFOV="${1}"
    CYL="${2}"
    EQR="${3}"
    OPTS="${4}"
    projectFile=project.pto

    # create a panotools project file:
    /Applications/Hugin/Hugin.app/Contents/MacOS/pto_gen -p 1 -f "${HFOV}" -o "${projectFile}" "${CYL}"
    # specify the eqr parameters
    /Applications/Hugin/Hugin.app/Contents/MacOS/pano_modify --fov=360x180 ${OPTS} --canvas=AUTO -o "${projectFile}" "${projectFile}"
    # create the EQR tiff
    /Applications/Hugin/HuginStitchProject.app/Contents/MacOS/nona -o "${EQR}" -m TIFF "${projectFile}" -z LZW
    rm ${projectFile}
}

function cube2eqr()
{
    if [ $# -ne 3 ]; then
        echo "wrong number of args for cube2eqr: $#"
        while [ $# -gt 0 ]; do
            echo $1
            shift
        done
        echo "cube2eqr <format> <inputTif> <outputTif>"
        echo "\n\tvalid formats include \"unity6x1\""
        exit 1
    fi
    format="${1}"
    inputPath="${2}"
    outputTif="${3}"
    if [ "${format}" != "unity6x1" ]; then
        echo "I dont know how to process ${format}"
        exit 1
    fi
    if [ ! -f "${inputPath}" ]; then
        echo "missing input file: ${inputPath}"
        exit 1
    fi
    # figure out the dimensions:
    dims=$(identify "${inputPath}" | perl -pe 's/(.+) (\d+)x(\d+)(.+)/$2 $3/g')
    width=$(echo $dims | cut -f1 -d\ )
    height=$(echo $dims | cut -f2 -d\ )
    if [ $((height * 6)) -ne ${width} ] ; then
        echo "not a 6x1 strip!"
        exit 1
    fi
    # make a tmpdir
    inputFile=$(basename $inputPath | tr -d "\r\n")
    tmpDir="./${inputFile}.tmp"
    mkdir -p "${tmpDir}"
    # chop the source image into faces:
    for x in 0 1 2 3 4 5; do
        offset=$((x * ${height}))
        #convert -crop 2048x2048+${offset}+0\! "${inputPath}" "${tmpDir}/${x}.tif"
    done

    # now make the eqr:
    #/opt/local/libexec/perl5.24/sitebin/cubic2erect ${tmpDir}/front.tif ${tmpDir}/right.tif ${tmpDir}/back.tif ${tmpDir}/left.tif ${tmpDir}/up.tif ${tmpDir}/down.tif ${outputTif}
    PATH=$PATH:/Applications/Hugin/PTBatcherGUI.app/Contents/MacOS /opt/local/libexec/perl5.24/sitebin/cubic2erect ${tmpDir}/4.tif ${tmpDir}/0.tif ${tmpDir}/5.tif ${tmpDir}/1.tif ${tmpDir}/2.tif ${tmpDir}/3.tif ${outputTif}
    echo "note that you may need to convert to jpg, scale to 6000x3000, and add metadata in order to post on facebook:"
    echo "convert -scale 6000x3000 $outputTif equirect.jpg"
    echo "exiftool -ProjectionType=\"equirectangular\" equirect.jpg"
}

function eqr2cube()
{
    if [ $# -lt 4 ]; then
        echo "not enough args for eqr2cube"
        echo 'eq2rcube <format> <edge length> <inputTif> <outputTif>'
        echo "\n\tvalid formats include \"360app\""
        exit 1
    fi
    format="${1}"
    edge="${2}"
    inputTif="${3}"
    outputTif="${4}"
    
    b=`basename "${inputTif}" .tif`
    inputTif="${PWD}/${inputTif}"

    # should be a mktemp soon XXX TODO
    tmpdir="${b}.tmp"

    mkdir -p "$tmpdir"
    outputPto="${tmpdir}/${b}.pto"

    /opt/local/libexec/perl5.24/sitebin/erect2cubic --face=${edge} --erect="${inputTif}" --ptofile="${outputPto}" 

    pushd "${tmpdir}"

    # faces created in the following order: front, right, back, left, up, down
    /Applications/Hugin/PTBatcherGUI.app/Contents/MacOS/nona -o cube_prefix "${b}.pto" -z LZW

    # default layout is to do nothing:
    flipList=""
    flopList=""
    faceOrder=cube_prefix000[0-5].tif
    
    if [ ${format} = "360app" ] ; then
        # "Oculus 360 Photos" app requires its own special cubemap layout:

        # flip turns things upside down
        flipList="4 5"

        # flop yields a mirror image
        flopList="0 1 2 3"
        faceOrder=cube_prefix000{1,3,4,5,2,0}.tif
    fi

    for x in ${flipList}; do 
        convert cube_prefix000${x}.tif -flip tmp.tif;
        mv tmp.tif cube_prefix000${x}.tif
    done

    for x in ${flopList}; do 
        convert cube_prefix000${x}.tif -flop tmp.tif;
        mv tmp.tif cube_prefix000${x}.tif
    done

    eval montage ${faceOrder} -tile 6x1 -geometry ${edge}x${edge}+0+0 ../${outputTif}

    popd
    rm -rf "${tmpdir}"
}

function flatten() 
{
    if [ $# -lt 1 ]; then
        echo "not enough args for flatten"
        echo "flatten <inputTif>"
        exit 1
    fi
    EQR="${1}"

    # need a mktemp XXX TODO
    convert -flatten "${EQR}" -background black -alpha remove flat.tif
    mv flat.tif "${EQR}"
}

function adjustHorizon() 
{
    if [ $# -lt 2 ]; then
        echo "not enough args for adjustHorizon"
        echo "adjustHorizon <geom> <horizonPixelAdjust> <inputTif>"
        exit 1
    fi
    geom="${1}"
    horizonOffset="${2}"
    EQR="${3}"
    echo adjusting horizon by $horizonOffset pixels

    # need a mktemp XXX TODO
    convert "${EQR}" -crop ${geom}+0+${horizonOffset}\! -background black -flatten -alpha remove horiz.tif
    mv horiz.tif "${EQR}"
}

function process()
{
    if [ $# -lt 8 ]; then
        echo "wrong number of args for process()"
        exit 1
    fi
    SRC="${1}"
    HFOV="${2}"
    OPTS="${3}"
    EQR="${4}"
    FACE="${5}"
    CUBE="${6}"
    GEOM="${7}"
    HORIZ="${8}"

    if [ ! -f "${EQR}" ] ; then
        cyl2eqr "${HFOV}" "${SRC}" "${EQR}" "${OPTS}"
        if [ ! -z "${HORIZ}" -a ! -z "${GEOM}" ]; then
            if [  ${HORIZ} -ne 0 ]; then
                adjustHorizon "${GEOM}" "${HORIZ}" "${EQR}"
            else
                flatten "${EQR}"
            fi
        else
            flatten "${EQR}"
        fi
        rm -f "${CUBE}"
    fi
    if [ ! -f "${CUBE}" ]; then
        eqr2cube 360app "${FACE}" "${EQR}" "${CUBE}"
    fi
}

function batch ()
{
    if [ $# -lt 3 ]; then
        echo "not enough args for batch()"
        exit 1
    fi
    inputDir="${1}"
    shift
    outputDir="${1}"
    shift
    while [ $# -gt 0 ]; do
        tsvFile="${1}"
        echo processing $tsvFile
        grep -v '^#' "${tsvFile}" | grep . | while read line; do
            SRC=`echo "$line"| cut -f1 -d$'\t'`
            HFOV=`echo "$line"| cut -f2 -d$'\t'`
            OPTS=`echo "$line"| cut -f3 -d$'\t'`
            EQR=`echo "$line"| cut -f4 -d$'\t'`
            FACE=`echo "$line"| cut -f5 -d$'\t'`
            CUBE=`echo "$line"| cut -f6 -d$'\t'`
            GEOM=`echo "$line"| cut -f7 -d$'\t'`
            HORIZ=`echo "$line"| cut -f8 -d$'\t'`
            process "${inputDir}/${SRC}" "${HFOV}" "${OPTS}" "${outputDir}/${EQR}" "${FACE}" "${outputDir}/${CUBE}" "${GEOM}" "${HORIZ}"
        done
        shift
    done
}

function usage()
{
    echo
    echo valid commands are cyl2eqr, eqr2cube, adjustHorizon, flatten, process, batch
    echo more usage goes here
    exit 1
}

if [ $# -lt 1 ]; then
    echo "not enough args"
    usage
fi

cmd=${1}
shift
if [ $cmd = "eqr2cube" ]; then
    eqr2cube ${@}
elif [ $cmd = "cyl2eqr" ]; then
    cyl2eqr ${@}
elif [ $cmd = "cube2eqr" ]; then
    # figure out if putting $@ in quotes is needed everywhere else too! XXX TODO
    cube2eqr "${@}"
elif [ $cmd = "adjustHorizon" ]; then
    adjustHorizon ${@}
elif [ $cmd = "process" ]; then
    process ${@}
elif [ $cmd = "batch" ]; then
    batch ${@}
else
    echo "unknown command: $cmd"
    usage 
fi
