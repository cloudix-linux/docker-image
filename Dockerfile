FROM scratch
ADD cloudix-linux-fs.tar.bz2 /

# minor docker-specific tweaks can be placed here

# overwrite this with 'CMD []' in a dependent Dockerfile
CMD ["/bin/bash"]
