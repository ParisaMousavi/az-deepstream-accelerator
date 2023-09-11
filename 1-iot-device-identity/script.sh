# Create a device identity for your simulated device so that it can communicate with your IoT hub
# The device identity lives in the cloud, and you use a unique device connection string to associate a physical device to a device identity.

az extension add --name azure-iot
echo "Checking if you have up-to-date Azure IoT 'azure-iot' extension..."
echo "--------------------------------------\n"
az extension show --name "azure-iot" &> extension_output
if cat extension_output | grep -q "not installed"; then
az extension add --name "azure-iot"
rm extension_output
else
az extension update --name "azure-iot"
rm extension_output
fi
echo ""

# create a device named myEdgeDevice in your hub
az iot hub device-identity create --device-id ${iothub_device_name} --edge-enabled --hub-name ${iothub_name} --output none

# View the connection string for your device, which links your physical device with its identity in IoT Hub
az iot hub device-identity connection-string show --device-id ${iothub_device_name} --hub-name ${iothub_name}


