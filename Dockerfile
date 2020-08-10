FROM python
RUN pip install --no-cache-dir pyze && \
	apt-get update && \
	apt-get install -y curl bc && \
    apt-get clean && \
	rm -rf /var/lib/apt/lists/* && \
    mkdir /root/.credentials
ADD renault.sh /renault.sh
ADD home.sh /home.sh
ADD pyze.json /root/.credentials/pyze.json
RUN chmod +x /renault.sh
CMD ["/renault.sh"]
