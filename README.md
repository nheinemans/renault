1. Create Docker image:
```
touch pyze.json
docker build -t renault .
```

2. Generate pyze.json:
```
docker run -v $(pwd)/pyze.json:/root/.credentials/pyze.json -e GIGYA_API_KEY=3_e8d4g4SE_Fo8ahyHwwP7ohLGZ79HKNN2T8NjQqoNnk6Epj6ilyYwKdHUyCw3wuxz -e KAMEREON_API_KEY=oF09WnKqvBDcrQzcW1rJNpjIuy7KdGaB -it --rm renault pyze login
```

3. Update Docker image with pyze.json (which contains your Renault login info):
```
docker build -t renault .
```

4. Get a list of all vehicles in your account:
```
docker run --rm renault pyze vehicles
```

5. Run the container every 5 minutes to send metrics to InfluxDB:
```
docker run --rm -e VIN=<VIN> renault
```
