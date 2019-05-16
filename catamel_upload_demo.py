#!/usr/bin/env python3
# demo script, uploading some data to a catamel instance, from javascript:
# https://github.com/SciCatProject/scicat-develop/blob/master/create-data/index.js

import sys
import numpy as np
import requests # for HTTP requests
import json     # for easy parsing
import loremipsum

host = "ws5490"
baseurl = "http://"+host+":3000/api/v3/"
numProposals = 50
numDatasetsPerProposal = [5, 15]
numDatafilesPerDataset = [5, 15]
bytesPerDatafile = [int(100e6), int(100e6)]

# np.random.randint
# np.random.choice

print("start ...")
response = requests.post(baseurl+"Users/login",
    json={ 'username': 'ingestor', 'password': 'aman' })
if not response.ok:
    err = response.json()['error']
    print(err['name'], err['statusCode'], ":", err['message'])
    sys.exit(1) # does not make sense to continue here

data = response.json()
print("Response:", data)
token = data['id'] # not sure if semantically correct
print("token:", token)

def createProposals(token):
    ownerGroups = ['group-1', 'group-2', 'group-3']
    owners = ['owner-1', 'owner-2', 'owner-3']
    beamlines = ['FooMAX', 'BarMAX', 'BazMAX']
    for i in range(numProposals):
        ownerGroup = np.random.choice(ownerGroups)
        owner = np.random.choice(owners)
        beamline = np.random.choice(beamlines)
        proposalId = "proposal-{}".format(i)
        email = "{}@email.com".format(owner)
        title = "Proposal {}".format(i)
        abstract = loremipsum.generate(3)

# vim: set ts=4 sw=4 sts=4 tw=0 et:
